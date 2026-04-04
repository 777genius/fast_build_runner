import 'dart:async';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/src/clients/build_resolvers/build_resolvers.dart';
import 'package:build/build.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:pool/pool.dart';

import 'package:build_runner/src/build/input_tracker.dart';
import 'package:build_runner/src/build/library_cycle_graph/phased_reader.dart';
import 'package:build_runner/src/logging/timed_activities.dart';

import 'fast_analysis_driver_filesystem.dart';
import 'fast_analysis_driver_model.dart';

class FastBuildResolver {
  final FastAnalysisDriverModel _analysisDriverModel;
  final AnalysisDriverForPackageBuild _driver;
  final AnalyzeActivityPool _driverPool;

  Future<List<LibraryElement>>? _sdkLibraries;

  FastBuildResolver(
    this._driver,
    Pool driverPool,
    this._analysisDriverModel,
  ) : _driverPool = AnalyzeActivityPool(driverPool);

  Future<bool> isLibrary(AssetId assetId) async {
    if (assetId.extension != '.dart') return false;
    return _driverPool.withResource(() async {
      if (!_driver.isUriOfExistingFile(assetId.uri)) return false;
      final result =
          _driver.currentSession.getFile(
                FastAnalysisDriverFilesystem.assetPath(assetId),
              )
              as FileResult;
      return !result.isPart;
    });
  }

  Future<AstNode?> astNodeFor(Fragment fragment, {bool resolve = false}) async {
    final library = fragment.libraryFragment?.element;
    if (library == null) {
      return null;
    }
    final path = library.firstFragment.source.fullName;

    return _driverPool.withResource(() async {
      final session = _driver.currentSession;
      if (resolve) {
        final result =
            await session.getResolvedLibrary(path) as ResolvedLibraryResult;
        if (fragment is LibraryFragment) {
          return result.unitWithPath(fragment.source.fullName)?.unit;
        }
        return result.getFragmentDeclaration(fragment)?.node;
      } else {
        final result = session.getParsedLibrary(path) as ParsedLibraryResult;
        if (fragment is LibraryFragment) {
          final unitPath = fragment.source.fullName;
          return result.units
              .firstWhereOrNull((unit) => unit.path == unitPath)
              ?.unit;
        }
        return result.getFragmentDeclaration(fragment)?.node;
      }
    });
  }

  Future<CompilationUnit> compilationUnitFor(
    AssetId assetId, {
    bool allowSyntaxErrors = false,
  }) {
    return _driverPool.withResource(() async {
      if (!_driver.isUriOfExistingFile(assetId.uri)) {
        throw AssetNotFoundException(assetId);
      }

      final path = FastAnalysisDriverFilesystem.assetPath(assetId);
      final parsedResult =
          _driver.currentSession.getParsedUnit(path) as ParsedUnitResult;
      if (!allowSyntaxErrors &&
          parsedResult.diagnostics.any((e) => e.severity == Severity.error)) {
        throw SyntaxErrorInAssetException(assetId, [parsedResult]);
      }
      return parsedResult.unit;
    });
  }

  Future<LibraryElement> libraryFor(
    AssetId assetId, {
    bool allowSyntaxErrors = false,
  }) async {
    final library = await _driverPool.withResource(() async {
      final uri = assetId.uri;
      if (!_driver.isUriOfExistingFile(uri)) {
        throw AssetNotFoundException(assetId);
      }

      final path = FastAnalysisDriverFilesystem.assetPath(assetId);
      final parsedResult = _driver.currentSession.getParsedUnit(path);
      if (parsedResult is! ParsedUnitResult || parsedResult.isPart) {
        throw NonLibraryAssetException(assetId);
      }

      return await _driver.currentSession.getLibraryByUri(uri.toString())
          as LibraryElementResult;
    });

    if (!allowSyntaxErrors) {
      final errors = await _syntacticErrorsFor(library.element);
      if (errors.isNotEmpty) {
        throw SyntaxErrorInAssetException(assetId, errors);
      }
    }

    return library.element;
  }

  Future<List<AnalysisResultWithDiagnostics>> _syntacticErrorsFor(
    LibraryElement element,
  ) async {
    final parsedLibrary = _driver.currentSession.getParsedLibraryByElement(
      element,
    );
    if (parsedLibrary is! ParsedLibraryResult) {
      return const [];
    }

    final relevantResults = <AnalysisResultWithDiagnostics>[];
    for (final unit in parsedLibrary.units) {
      if (unit.diagnostics.any(
        (error) => error.diagnosticCode.type == DiagnosticType.SYNTACTIC_ERROR,
      )) {
        relevantResults.add(unit);
      }
    }
    return relevantResults;
  }

  Stream<LibraryElement> get sdkLibraries {
    final loadLibraries = _sdkLibraries ??= Future.sync(() {
      final publicSdkUris = _driver.sdkLibraryUris.where(
        (e) => !e.path.startsWith('_'),
      );

      return Future.wait(
        publicSdkUris.map((uri) {
          return _driverPool.withResource(() async {
            final result =
                await _driver.currentSession.getLibraryByUri(uri.toString())
                    as LibraryElementResult;
            return result.element;
          });
        }),
      );
    });

    return Stream.fromFuture(loadLibraries).expand((libraries) => libraries);
  }

  Future<AssetId> assetIdForElement(Element element) async {
    if (element is MultiplyDefinedElement) {
      throw UnresolvableAssetException('${element.name} is ambiguous');
    }

    final source = element.firstFragment.libraryFragment?.source;
    if (source == null) {
      throw UnresolvableAssetException(
        '${element.name} does not have a source',
      );
    }

    final uri = source.uri;
    if (!uri.isScheme('package') && !uri.isScheme('asset')) {
      throw UnresolvableAssetException('${element.name} in ${source.uri}');
    }
    return AssetId.resolve(source.uri);
  }

  Future<void> updateDriverForEntrypoint({
    required AssetId entrypoint,
    required PhasedReader phasedReader,
    required InputTracker inputTracker,
    required bool transitive,
  }) => _analysisDriverModel.updateDriver(
    withDriver:
        (withDriver) => _driverPool.withResource(() => withDriver(_driver)),
    phasedReader: phasedReader,
    inputTracker: inputTracker,
    entrypoint: entrypoint,
    transitive: transitive,
  );
}

class AnalyzeActivityPool {
  final Pool pool;

  AnalyzeActivityPool(this.pool);

  Future<T> withResource<T>(Future<T> Function() function) async {
    return pool.withResource(() => TimedActivity.analyze.runAsync(function));
  }
}
