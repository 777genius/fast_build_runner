import 'dart:async';
import 'dart:collection';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:pool/pool.dart';

import 'package:build_runner/src/build/build_step_impl.dart';
import 'package:build_runner/src/build/resolver/build_resolver.dart';
import 'package:build_runner/src/build/resolver/build_step_resolver.dart';

/// Narrow fork of upstream [BuildStepResolver].
///
/// The upstream implementation already memoizes transitive entrypoint syncing
/// per action, but repeated non-transitive `isLibrary` / `compilationUnitFor`
/// calls still re-run `updateDriverForEntrypoint` for the same asset in the
/// same build step. On large `source_gen` workloads this shows up as repeated
/// `Resolving library ...` / `isLibrary ...` hotspots for the same file.
///
/// This fork keeps the same correctness boundary while caching:
/// - non-transitive driver syncs per action
/// - `canRead` per asset
/// - `isLibrary` / `libraryFor` / `compilationUnitFor` per asset
class FastBuildStepResolver implements ReleasableResolver {
  final BuildResolver _buildResolver;
  final BuildStepImpl _buildStep;
  final Map<String, Future<void>> _sharedResolveSyncCache;

  final _entryPoints = <AssetId>{};
  final _nonTransitiveSyncedEntrypoints = <AssetId>{};
  final _perActionResolvePool = Pool(1);

  final _canReadCache = <AssetId, Future<bool>>{};
  final _isLibraryCache = <AssetId, Future<bool>>{};
  final _compilationUnitCache = <_AssetReadKey, Future<CompilationUnit>>{};
  final _libraryCache = <_AssetReadKey, Future<LibraryElement>>{};

  FastBuildStepResolver(
    this._buildResolver,
    this._buildStep, {
    required Map<String, Future<void>> sharedResolveSyncCache,
  }) : _sharedResolveSyncCache = sharedResolveSyncCache;

  Stream<LibraryElement> get _librariesFromEntrypoints async* {
    await _updateDriverForEntrypoint(_buildStep.inputId, transitive: true);

    final seen = <LibraryElement>{};
    final toVisit = Queue<LibraryElement>();

    final entryPoints = _entryPoints.toList();
    for (final entryPoint in entryPoints) {
      if (!await _readIsLibrary(entryPoint)) continue;
      final library = await _readLibraryFor(
        entryPoint,
        allowSyntaxErrors: true,
      );
      toVisit.add(library);
      seen.add(library);
    }
    while (toVisit.isNotEmpty) {
      final current = toVisit.removeFirst();
      yield current;
      final toCrawl = current.firstFragment.libraryImports
          .map((import) => import.importedLibrary)
          .followedBy(
            current.firstFragment.libraryExports.map(
              (export) => export.exportedLibrary,
            ),
          )
          .nonNulls
          .where((library) => !seen.contains(library))
          .toSet();
      toVisit.addAll(toCrawl);
      seen.addAll(toCrawl);
    }
  }

  @override
  Stream<LibraryElement> get libraries async* {
    yield* _buildResolver.sdkLibraries;
    yield* _librariesFromEntrypoints.where((library) => !library.isInSdk);
  }

  @override
  Future<LibraryElement?> findLibraryByName(String libraryName) =>
      _buildStep.trackStage('findLibraryByName $libraryName', () async {
        await for (final library in libraries) {
          if (library.name == libraryName) return library;
        }
        return null;
      });

  @override
  Future<bool> isLibrary(AssetId assetId) => _buildStep.trackStage(
    'isLibrary $assetId',
    () => _readIsLibrary(assetId),
  );

  @override
  Future<AstNode?> astNodeFor(Fragment fragment, {bool resolve = false}) =>
      _buildStep.trackStage(
        'astNodeFor $fragment',
        () => _buildResolver.astNodeFor(fragment, resolve: resolve),
      );

  @override
  Future<CompilationUnit> compilationUnitFor(
    AssetId assetId, {
    bool allowSyntaxErrors = false,
  }) => _buildStep.trackStage(
    'compilationUnitFor $assetId',
    () =>
        _readCompilationUnitFor(assetId, allowSyntaxErrors: allowSyntaxErrors),
  );

  @override
  Future<LibraryElement> libraryFor(
    AssetId assetId, {
    bool allowSyntaxErrors = false,
  }) => _buildStep.trackStage(
    'libraryFor $assetId',
    () => _readLibraryFor(assetId, allowSyntaxErrors: allowSyntaxErrors),
  );

  Future<bool> _canRead(AssetId assetId) =>
      _canReadCache.putIfAbsent(assetId, () => _buildStep.canRead(assetId));

  Future<bool> _readIsLibrary(AssetId assetId) =>
      _isLibraryCache.putIfAbsent(assetId, () async {
        if (!await _canRead(assetId)) return false;
        await _updateDriverForEntrypoint(assetId, transitive: false);
        return _buildResolver.isLibrary(assetId);
      });

  Future<CompilationUnit> _readCompilationUnitFor(
    AssetId assetId, {
    required bool allowSyntaxErrors,
  }) {
    final key = _AssetReadKey(
      assetId: assetId,
      allowSyntaxErrors: allowSyntaxErrors,
    );
    return _compilationUnitCache.putIfAbsent(key, () async {
      if (!await _canRead(assetId)) {
        throw AssetNotFoundException(assetId);
      }
      await _updateDriverForEntrypoint(assetId, transitive: false);
      return _buildResolver.compilationUnitFor(
        assetId,
        allowSyntaxErrors: allowSyntaxErrors,
      );
    });
  }

  Future<LibraryElement> _readLibraryFor(
    AssetId assetId, {
    required bool allowSyntaxErrors,
  }) {
    final key = _AssetReadKey(
      assetId: assetId,
      allowSyntaxErrors: allowSyntaxErrors,
    );
    return _libraryCache.putIfAbsent(key, () async {
      if (!await _canRead(assetId)) {
        throw AssetNotFoundException(assetId);
      }
      await _updateDriverForEntrypoint(assetId, transitive: true);
      return _buildResolver.libraryFor(
        assetId,
        allowSyntaxErrors: allowSyntaxErrors,
      );
    });
  }

  Future<void> _updateDriverForEntrypoint(
    AssetId entrypoint, {
    required bool transitive,
  }) => _perActionResolvePool.withResource(() async {
    final phase = _buildStep.phasedReader.phase;
    if (transitive) {
      if (_entryPoints.contains(entrypoint)) return;
      _buildStep.inputTracker.addResolverEntrypoint(entrypoint);
      await _sharedSync(
        entrypoint,
        phase: phase,
        transitive: true,
        runResolve: () => _buildStep.trackStage(
          'Resolving library $entrypoint',
          () => _buildResolver.updateDriverForEntrypoint(
            phasedReader: _buildStep.phasedReader,
            inputTracker: _buildStep.inputTracker,
            entrypoint: entrypoint,
            transitive: true,
          ),
        ),
      );
      _entryPoints.add(entrypoint);
      _nonTransitiveSyncedEntrypoints.add(entrypoint);
      return;
    }

    if (_entryPoints.contains(entrypoint) ||
        _nonTransitiveSyncedEntrypoints.contains(entrypoint)) {
      return;
    }

    _buildStep.inputTracker.add(entrypoint);
    await _sharedSync(
      entrypoint,
      phase: phase,
      transitive: false,
      runResolve: () => _buildStep.trackStage(
        'Resolving library $entrypoint',
        () => _buildResolver.updateDriverForEntrypoint(
          phasedReader: _buildStep.phasedReader,
          inputTracker: _buildStep.inputTracker,
          entrypoint: entrypoint,
          transitive: false,
        ),
      ),
    );
    _nonTransitiveSyncedEntrypoints.add(entrypoint);
  });

  Future<void> _sharedSync(
    AssetId entrypoint, {
    required int phase,
    required bool transitive,
    required Future<void> Function() runResolve,
  }) async {
    final requestedKey = _sharedResolveKey(
      entrypoint: entrypoint,
      phase: phase,
      transitive: transitive,
    );
    final compatibleKey = transitive
        ? requestedKey
        : _sharedResolveKey(
            entrypoint: entrypoint,
            phase: phase,
            transitive: true,
          );

    final compatibleFuture = _sharedResolveSyncCache[compatibleKey];
    if (compatibleFuture != null) {
      await compatibleFuture;
      return;
    }

    final existingFuture = _sharedResolveSyncCache[requestedKey];
    if (existingFuture != null) {
      await existingFuture;
      return;
    }

    late final Future<void> resolveFuture;
    resolveFuture = runResolve().catchError((Object error, StackTrace stack) {
      _sharedResolveSyncCache.remove(requestedKey);
      throw error;
    });
    _sharedResolveSyncCache[requestedKey] = resolveFuture;
    await resolveFuture;
  }

  @override
  void release() {}

  @override
  Future<AssetId> assetIdForElement(Element element) =>
      _buildResolver.assetIdForElement(element);
}

class _AssetReadKey {
  final AssetId assetId;
  final bool allowSyntaxErrors;

  const _AssetReadKey({required this.assetId, required this.allowSyntaxErrors});

  @override
  bool operator ==(Object other) =>
      other is _AssetReadKey &&
      other.assetId == assetId &&
      other.allowSyntaxErrors == allowSyntaxErrors;

  @override
  int get hashCode => Object.hash(assetId, allowSyntaxErrors);
}

String _sharedResolveKey({
  required AssetId entrypoint,
  required int phase,
  required bool transitive,
}) => '${entrypoint.package}|${entrypoint.path}|$phase|$transitive';
