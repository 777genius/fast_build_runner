// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:io';

import 'package:build/build.dart';
import 'package:build_runner/src/internal.dart';
import 'package:built_collection/built_collection.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'bootstrap_spike_result.dart';
import 'fast_build_plan.dart';
import 'fast_build_series.dart';
import 'fast_watch_scheduler.dart';
import 'rust_daemon_client.dart';
import 'watch_alpha_result.dart';
import 'watch_update_merger.dart';

class FastWatchAlphaSession {
  final BuilderFactories builderFactories;
  final String upstreamCommit;

  const FastWatchAlphaSession({
    required this.builderFactories,
    required this.upstreamCommit,
  });

  Future<FastWatchAlphaResult> run({
    required String sourceEngine,
    required String? rustDaemonDirectory,
    required String packageName,
    required String sourceFileRelativePath,
    required String generatedFileRelativePath,
    required String generatedEntrypointPath,
    required String runDirectory,
    required bool mutateBuildScriptBeforeIncremental,
  }) async {
    final buildPlan = await FastBuildPlan.load(
      builderFactories: builderFactories,
      buildOptions: BuildOptions(
        buildDirs: BuiltSet<BuildDirectory>(),
        builderConfigOverrides: BuiltMap<String, BuiltMap<String, Object?>>(),
        buildFilters: BuiltSet<BuildFilter>(),
        configKey: null,
        dartAotPerf: false,
        enableExperiments: BuiltList<String>(),
        enableLowResourcesMode: false,
        forceAot: false,
        forceJit: false,
        isReleaseBuild: false,
        logPerformanceDir: null,
        outputSymlinksOnly: false,
        trackPerformance: false,
        verbose: false,
        verboseDurations: false,
        workspace: false,
      ),
      testingOverrides: const TestingOverrides(),
      recentlyBootstrapped: true,
    );

    await buildPlan.deleteFilesAndFolders();
    if (buildPlan.restartIsNeeded) {
      return FastWatchAlphaResult(
        status: 'deferred',
        sourceEngine: sourceEngine,
        upstreamCommit: upstreamCommit,
        generatedEntrypointPath: generatedEntrypointPath,
        runDirectory: runDirectory,
        warnings: const [
          'FastBuildPlan reported restartIsNeeded during watch alpha bootstrap.',
        ],
        errors: const [],
        observedEvents: const [],
        mergedUpdates: const [],
        initialBuild: null,
        incrementalBuild: null,
      );
    }

    final buildSeries = FastBuildSeries(buildPlan);
    final buildResults = <BuildResult>[];
    final scheduler = FastWatchScheduler<BuildResult>(
      onBuild: (updates) =>
          buildSeries.run(updates, recentlyBootstrapped: false),
    );
    StreamSubscription<BuildResult>? resultSubscription;
    try {
      final initialBuild = await buildSeries.run(
        {},
        recentlyBootstrapped: true,
      );
      final initialResult = _stepResult(
        name: 'initial',
        buildResult: initialBuild,
        generatedFileRelativePath: generatedFileRelativePath,
      );

      final observedEvents = <String>[];
      resultSubscription = scheduler.results.listen(buildResults.add);
      final watchBatch = await _collectWatchBatch(
        sourceEngine: sourceEngine,
        rustDaemonDirectory: rustDaemonDirectory,
        packageName: packageName,
        sourceFileRelativePath: sourceFileRelativePath,
        generatedEntrypointPath: generatedEntrypointPath,
        mutateBuildScriptBeforeIncremental: mutateBuildScriptBeforeIncremental,
      );
      observedEvents.addAll(watchBatch.observedEvents);
      final mergedUpdates = watchBatch.mergedUpdates;
      final sourceAssetId = AssetId(packageName, sourceFileRelativePath);

      await scheduler.enqueue(mergedUpdates);
      final incrementalBuild = buildResults.isNotEmpty
          ? buildResults.last
          : throw StateError(
              'Watch alpha scheduler became idle without producing a build result.',
            );
      final incrementalResult = _stepResult(
        name: 'incremental',
        buildResult: incrementalBuild,
        generatedFileRelativePath: generatedFileRelativePath,
      );

      final success =
          initialBuild.status == BuildStatus.success &&
          (mutateBuildScriptBeforeIncremental
              ? incrementalResult.failureType == 'buildScriptChanged'
              : incrementalBuild.status == BuildStatus.success &&
                    incrementalResult.generatedFileHasMutation &&
                    mergedUpdates.length == 1 &&
                    mergedUpdates.containsKey(sourceAssetId));

      return FastWatchAlphaResult(
        status: success ? 'success' : 'failure',
        sourceEngine: sourceEngine,
        upstreamCommit: upstreamCommit,
        generatedEntrypointPath: generatedEntrypointPath,
        runDirectory: runDirectory,
        warnings: [
          if (sourceEngine == 'rust')
            'Watch alpha used the Rust daemon as the filesystem event source.',
          if (mutateBuildScriptBeforeIncremental)
            'The generated entrypoint was intentionally mutated during watch alpha to verify buildScriptChanged handling.',
        ],
        errors: [
          ...initialResult.errors,
          ...incrementalResult.errors,
          if (observedEvents.isEmpty)
            'Watch alpha completed without observing any filesystem events.',
          if (watchBatch.isEmpty)
            'Watch alpha did not collect a non-empty event batch.',
          if (!mutateBuildScriptBeforeIncremental &&
              !incrementalResult.generatedFileHasMutation)
            'Watch alpha incremental rebuild finished without the expected generated output mutation.',
          if (!mutateBuildScriptBeforeIncremental && mergedUpdates.length != 1)
            'Watch alpha expected a merged single-asset update batch for source burst verification.',
          if (mutateBuildScriptBeforeIncremental &&
              incrementalResult.failureType != 'buildScriptChanged')
            'Watch alpha did not surface buildScriptChanged after the generated entrypoint was mutated.',
        ],
        observedEvents: observedEvents,
        mergedUpdates: mergedUpdates.entries
            .map((entry) => '${entry.key}:${entry.value}')
            .toList(),
        initialBuild: initialResult,
        incrementalBuild: incrementalResult,
      );
    } finally {
      await resultSubscription?.cancel();
      await scheduler.close();
      await buildSeries.close();
    }
  }

  Future<_CollectedWatchBatch> _collectWatchBatch({
    required String sourceEngine,
    required String? rustDaemonDirectory,
    required String packageName,
    required String sourceFileRelativePath,
    required String generatedEntrypointPath,
    required bool mutateBuildScriptBeforeIncremental,
  }) {
    switch (sourceEngine) {
      case 'rust':
        return _collectRustWatchBatch(
          rustDaemonDirectory: rustDaemonDirectory,
          packageName: packageName,
          sourceFileRelativePath: sourceFileRelativePath,
          generatedEntrypointPath: generatedEntrypointPath,
          mutateBuildScriptBeforeIncremental:
              mutateBuildScriptBeforeIncremental,
        );
      case 'dart':
      default:
        return _collectDartWatchBatch(
          packageName: packageName,
          sourceFileRelativePath: sourceFileRelativePath,
          generatedEntrypointPath: generatedEntrypointPath,
          mutateBuildScriptBeforeIncremental:
              mutateBuildScriptBeforeIncremental,
        );
    }
  }

  Future<_CollectedWatchBatch> _collectDartWatchBatch({
    required String packageName,
    required String sourceFileRelativePath,
    required String generatedEntrypointPath,
    required bool mutateBuildScriptBeforeIncremental,
  }) async {
    StreamSubscription<WatchEvent>? subscription;
    Timer? quietTimer;
    try {
      final observedEvents = <String>[];
      final pendingEvents = <WatchEvent>[];
      final batchCompleter = Completer<List<WatchEvent>>();
      final watcher = DirectoryWatcher(Directory.current.path);
      subscription = watcher.events.listen((event) {
        observedEvents.add('${event.type}:${event.path}');
        if (!_shouldTrackRelativePath(
          _relativePath(event.path),
          sourceFileRelativePath,
        )) {
          return;
        }
        pendingEvents.add(event);
        quietTimer?.cancel();
        quietTimer = Timer(const Duration(milliseconds: 350), () {
          if (!batchCompleter.isCompleted) {
            batchCompleter.complete(List<WatchEvent>.from(pendingEvents));
          }
        });
      });
      await watcher.ready;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await _performWatchMutation(
        sourceFileRelativePath: sourceFileRelativePath,
        generatedEntrypointPath: generatedEntrypointPath,
        mutateBuildScriptBeforeIncremental: mutateBuildScriptBeforeIncremental,
      );

      final watchBatch = await batchCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'Timed out waiting for a watcher batch for $sourceFileRelativePath.',
        ),
      );
      return _CollectedWatchBatch(
        observedEvents: observedEvents,
        mergedUpdates: _collectDartChanges(packageName, watchBatch),
        isEmpty: watchBatch.isEmpty,
      );
    } finally {
      quietTimer?.cancel();
      await subscription?.cancel();
    }
  }

  Future<_CollectedWatchBatch> _collectRustWatchBatch({
    required String? rustDaemonDirectory,
    required String packageName,
    required String sourceFileRelativePath,
    required String generatedEntrypointPath,
    required bool mutateBuildScriptBeforeIncremental,
  }) async {
    if (rustDaemonDirectory == null || rustDaemonDirectory.isEmpty) {
      throw StateError(
        'Rust watch alpha requested, but no rust daemon directory was provided.',
      );
    }

    final client = RustDaemonClient(daemonDirectory: rustDaemonDirectory);
    final ping = await client.ping(id: 'watch-alpha-ping');
    if (ping is RustDaemonErrorResponse) {
      throw StateError('Rust daemon ping failed: ${ping.message}');
    }

    final watchFuture = client.watchOnce(
      id: 'watch-alpha-watch',
      path: Directory.current.path,
      debounceMs: 350,
      timeoutMs: 15000,
    );
    await Future<void>.delayed(const Duration(milliseconds: 750));
    await _performWatchMutation(
      sourceFileRelativePath: sourceFileRelativePath,
      generatedEntrypointPath: generatedEntrypointPath,
      mutateBuildScriptBeforeIncremental: mutateBuildScriptBeforeIncremental,
    );

    final response = await watchFuture;
    if (response is RustDaemonErrorResponse) {
      throw StateError('Rust daemon watchOnce failed: ${response.message}');
    }
    if (response is! RustDaemonWatchBatchResponse) {
      throw StateError(
        'Rust daemon returned an unexpected response type: ${response.runtimeType}',
      );
    }

    final observedEvents = response.events
        .map((event) => '${event.kind}:${event.path}')
        .toList();
    return _CollectedWatchBatch(
      observedEvents: observedEvents,
      mergedUpdates: _collectRustChanges(
        packageName,
        sourceFileRelativePath,
        response.events,
      ),
      isEmpty: response.events.isEmpty,
    );
  }

  Future<void> _performWatchMutation({
    required String sourceFileRelativePath,
    required String generatedEntrypointPath,
    required bool mutateBuildScriptBeforeIncremental,
  }) async {
    await _mutateFixtureSource(sourceFileRelativePath);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _appendSourceBurstComment(sourceFileRelativePath);
    if (mutateBuildScriptBeforeIncremental) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await _mutateBuildScript(generatedEntrypointPath);
    }
  }

  bool _shouldTrackRelativePath(
    String? relativePath,
    String sourceFileRelativePath,
  ) {
    if (relativePath == null) {
      return false;
    }
    return relativePath == sourceFileRelativePath ||
        relativePath == 'build.yaml' ||
        relativePath.startsWith('.dart_tool/build/entrypoint/');
  }

  String? _relativeEventPath(WatchEvent event) {
    return _relativePath(event.path);
  }

  String? _relativePath(String path) {
    final absolutePath = p.isAbsolute(path)
        ? path
        : p.join(Directory.current.path, path);
    if (!p.isWithin(Directory.current.path, absolutePath) &&
        !p.equals(Directory.current.path, absolutePath)) {
      return null;
    }
    return p.relative(absolutePath, from: Directory.current.path);
  }

  Map<AssetId, ChangeType> _collectDartChanges(
    String packageName,
    List<WatchEvent> changes,
  ) {
    final batches = <Map<AssetId, ChangeType>>[];
    for (final change in changes) {
      final relativePath = _relativeEventPath(change);
      if (relativePath == null) {
        continue;
      }
      batches.add({AssetId(packageName, relativePath): change.type});
    }
    return mergeAssetChangeMaps(batches);
  }

  Map<AssetId, ChangeType> _collectRustChanges(
    String packageName,
    String sourceFileRelativePath,
    List<RustDaemonWatchEvent> changes,
  ) {
    final batches = <Map<AssetId, ChangeType>>[];
    for (final change in changes) {
      final relativePath = _relativePath(change.path);
      if (!_shouldTrackRelativePath(relativePath, sourceFileRelativePath)) {
        continue;
      }
      final changeType = switch (change.kind) {
        'add' => ChangeType.ADD,
        'remove' => ChangeType.REMOVE,
        'modify' => ChangeType.MODIFY,
        _ => null,
      };
      if (relativePath == null || changeType == null) {
        continue;
      }
      batches.add({AssetId(packageName, relativePath): changeType});
    }
    return mergeAssetChangeMaps(batches);
  }

  FastBuildStepResult _stepResult({
    required String name,
    required BuildResult buildResult,
    required String generatedFileRelativePath,
  }) {
    final generatedFile = File(
      p.join(Directory.current.path, generatedFileRelativePath),
    );
    final generatedContent = generatedFile.existsSync()
        ? generatedFile.readAsStringSync()
        : '';
    return FastBuildStepResult(
      name: name,
      status: buildResult.status.name,
      failureType: _failureType(buildResult),
      outputs: buildResult.outputs.map((assetId) => '$assetId').toList(),
      errors: buildResult.errors.toList(),
      generatedFileExists: generatedFile.existsSync(),
      generatedFileHasMutation: generatedContent.contains('nickname'),
    );
  }

  String? _failureType(BuildResult buildResult) {
    final failureType = buildResult.failureType;
    if (failureType == null) {
      return null;
    }
    if (identical(failureType, FailureType.buildScriptChanged)) {
      return 'buildScriptChanged';
    }
    if (identical(failureType, FailureType.cantCreate)) {
      return 'cantCreate';
    }
    return 'general';
  }

  Future<void> _mutateBuildScript(String generatedEntrypointPath) async {
    final file = File(generatedEntrypointPath);
    if (!file.existsSync()) {
      throw StateError(
        'Cannot mutate generated entrypoint because it does not exist: $generatedEntrypointPath',
      );
    }
    final original = file.readAsStringSync();
    if (original.contains(
      '// fast_build_runner watch alpha mutated build script marker',
    )) {
      return;
    }
    file.writeAsStringSync(
      '$original\n// fast_build_runner watch alpha mutated build script marker\n',
    );
  }

  Future<void> _appendSourceBurstComment(String sourceFileRelativePath) async {
    final file = File(p.join(Directory.current.path, sourceFileRelativePath));
    final original = file.readAsStringSync();
    if (original.contains('// fast_build_runner watch alpha burst marker')) {
      return;
    }
    file.writeAsStringSync(
      '$original\n// fast_build_runner watch alpha burst marker\n',
    );
  }

  Future<void> _mutateFixtureSource(String sourceFileRelativePath) async {
    final file = File(p.join(Directory.current.path, sourceFileRelativePath));
    final original = file.readAsStringSync();
    if (original.contains('this.nickname') &&
        original.contains('final String? nickname;')) {
      return;
    }
    const constructorMarker = '  const Person({required this.name, this.age});';
    const fieldMarker = '  final int? age;';
    if (!original.contains(constructorMarker) ||
        !original.contains(fieldMarker)) {
      throw StateError(
        'Mutation markers not found in watch alpha fixture source.',
      );
    }
    final updated = original
        .replaceFirst(
          constructorMarker,
          '  const Person({required this.name, this.age, this.nickname});',
        )
        .replaceFirst(fieldMarker, '$fieldMarker\n  final String? nickname;');
    file.writeAsStringSync(updated);
  }
}

class _CollectedWatchBatch {
  final List<String> observedEvents;
  final Map<AssetId, ChangeType> mergedUpdates;
  final bool isEmpty;

  const _CollectedWatchBatch({
    required this.observedEvents,
    required this.mergedUpdates,
    required this.isEmpty,
  });
}
