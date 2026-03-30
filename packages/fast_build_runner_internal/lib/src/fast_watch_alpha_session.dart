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
import 'watch_batch_resolver.dart';
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
    required int incrementalCycles,
    required String? rustDaemonDirectory,
    required String packageName,
    required String sourceFileRelativePath,
    required String generatedFileRelativePath,
    required String generatedEntrypointPath,
    required String runDirectory,
    required bool mutateBuildScriptBeforeIncremental,
    required bool simulateDroppedSourceUpdateOnIncremental,
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
        observedEventBatches: const [],
        mergedUpdateBatches: const [],
        initialBuild: null,
        incrementalBuild: null,
        incrementalBuilds: const [],
      );
    }

    final buildSeries = FastBuildSeries(buildPlan);
    final buildResults = <BuildResult>[];
    final scheduler = FastWatchScheduler<BuildResult>(
      onBuild: (updates) =>
          buildSeries.run(updates, recentlyBootstrapped: false),
    );
    final sourceAssetId = AssetId(packageName, sourceFileRelativePath);
    RustDaemonSession? rustClient;
    int? rustDaemonStartupMilliseconds;
    StreamSubscription<BuildResult>? resultSubscription;

    try {
      final initialStopwatch = Stopwatch()..start();
      final initialBuild = await buildSeries.run(
        {},
        recentlyBootstrapped: true,
      );
      initialStopwatch.stop();
      final initialResult = _stepResult(
        name: 'initial',
        elapsedMilliseconds: initialStopwatch.elapsedMilliseconds,
        buildResult: initialBuild,
        generatedFileRelativePath: generatedFileRelativePath,
      );

      resultSubscription = scheduler.results.listen(buildResults.add);
      if (sourceEngine == 'rust') {
        final rustStartupStopwatch = Stopwatch()..start();
        rustClient = await _prepareRustSession(rustDaemonDirectory);
        rustStartupStopwatch.stop();
        rustDaemonStartupMilliseconds = rustStartupStopwatch.elapsedMilliseconds;
      }
      final observedEventBatches = <List<String>>[];
      final mergedUpdateBatches = <List<String>>[];
      final watchCollectionMilliseconds = <int>[];
      final incrementalResults = <FastBuildStepResult>[];
      final resolutionWarnings = <String>[];
      _CollectedWatchBatch? lastWatchBatch;

      for (var cycleIndex = 0; cycleIndex < incrementalCycles; cycleIndex++) {
        final watchCollectionStopwatch = Stopwatch()..start();
        final watchBatch = await _collectWatchBatch(
          sourceEngine: sourceEngine,
          rustClient: rustClient,
          packageName: packageName,
          sourceFileRelativePath: sourceFileRelativePath,
          generatedEntrypointPath: generatedEntrypointPath,
          mutateBuildScriptBeforeIncremental:
              cycleIndex == 0 && mutateBuildScriptBeforeIncremental,
          cycleIndex: cycleIndex,
        );
        watchCollectionStopwatch.stop();
        lastWatchBatch = watchBatch;

        final resolution = await resolveWatchBatch(
          watcherUpdates: _maybeDropExpectedSourceUpdate(
            updates: watchBatch.mergedUpdates,
            expectedSourceAssetId: sourceAssetId,
            simulateDrop:
                simulateDroppedSourceUpdateOnIncremental && cycleIndex == 0,
          ),
          watcherBatchWasEmpty: watchBatch.isEmpty,
          expectedSourceAssetId: sourceAssetId,
          collectSourceUpdates: buildSeries.collectSourceUpdates,
        );
        final mergedUpdates = resolution.updates;
        if (resolution.warning != null) {
          resolutionWarnings.add(
            'incremental-${cycleIndex + 1}: ${resolution.warning!}',
          );
        }
        observedEventBatches.add(List<String>.from(watchBatch.observedEvents));
        watchCollectionMilliseconds.add(
          watchCollectionStopwatch.elapsedMilliseconds,
        );
        mergedUpdateBatches.add(
          mergedUpdates.entries
              .map((entry) => '${entry.key}:${entry.value}')
              .toList(),
        );

        final expectedBuildCount = buildResults.length + 1;
        final incrementalStopwatch = Stopwatch()..start();
        await scheduler.enqueue(mergedUpdates);
        incrementalStopwatch.stop();
        if (buildResults.length < expectedBuildCount) {
          throw StateError(
            'Watch alpha scheduler became idle without producing build #$expectedBuildCount.',
          );
        }

        incrementalResults.add(
          _stepResult(
            name: 'incremental-${cycleIndex + 1}',
            elapsedMilliseconds: incrementalStopwatch.elapsedMilliseconds,
            buildResult: buildResults[expectedBuildCount - 1],
            generatedFileRelativePath: generatedFileRelativePath,
          ),
        );
      }

      final observedEvents = observedEventBatches
          .expand((batch) => batch)
          .toList(growable: false);
      final lastIncremental = incrementalResults.isEmpty
          ? null
          : incrementalResults.last;
      final lastMergedUpdates = mergedUpdateBatches.isEmpty
          ? const <String>[]
          : mergedUpdateBatches.last;

      final success =
          initialBuild.status == BuildStatus.success &&
          lastIncremental != null &&
          (mutateBuildScriptBeforeIncremental
              ? incrementalCycles == 1 &&
                    lastIncremental.failureType == 'buildScriptChanged'
              : incrementalResults.every((step) => step.status == 'success') &&
                    incrementalResults.every(
                      (step) => step.generatedFileHasMutation,
                    ) &&
                    mergedUpdateBatches.every((batch) => batch.length == 1) &&
                    mergedUpdateBatches.every(
                      (batch) => batch.single.contains('$sourceAssetId:'),
                    ));

      return FastWatchAlphaResult(
        status: success ? 'success' : 'failure',
        sourceEngine: sourceEngine,
        upstreamCommit: upstreamCommit,
        generatedEntrypointPath: generatedEntrypointPath,
        runDirectory: runDirectory,
        warnings: [
          if (sourceEngine == 'rust')
            'Watch alpha used the Rust daemon as the filesystem event source.',
          if (incrementalCycles > 1)
            'Watch alpha executed $incrementalCycles incremental cycles before exiting.',
          if (mutateBuildScriptBeforeIncremental)
            'The generated entrypoint was intentionally mutated during watch alpha to verify buildScriptChanged handling.',
          if (simulateDroppedSourceUpdateOnIncremental)
            'The first incremental cycle intentionally dropped the source update before resolution to verify filesystem resync recovery.',
          ...resolutionWarnings,
        ],
        errors: [
          ...initialResult.errors,
          ...incrementalResults.expand((step) => step.errors),
          if (observedEvents.isEmpty)
            'Watch alpha completed without observing any filesystem events.',
          if (lastWatchBatch == null || lastWatchBatch.isEmpty)
            'Watch alpha did not collect a non-empty event batch.',
          if (!mutateBuildScriptBeforeIncremental &&
              incrementalResults.any((step) => !step.generatedFileHasMutation))
            'Watch alpha finished at least one incremental rebuild without the expected generated output mutation.',
          if (!mutateBuildScriptBeforeIncremental &&
              mergedUpdateBatches.any((batch) => batch.length != 1))
            'Watch alpha expected every incremental cycle to resolve to a merged single-asset update batch.',
          if (mutateBuildScriptBeforeIncremental && incrementalCycles != 1)
            'Watch alpha currently supports buildScriptChanged verification only with a single incremental cycle.',
          if (mutateBuildScriptBeforeIncremental &&
              lastIncremental?.failureType != 'buildScriptChanged')
            'Watch alpha did not surface buildScriptChanged after the generated entrypoint was mutated.',
        ],
        observedEvents: observedEvents,
        mergedUpdates: lastMergedUpdates,
        observedEventBatches: observedEventBatches,
        mergedUpdateBatches: mergedUpdateBatches,
        rustDaemonStartupMilliseconds: rustDaemonStartupMilliseconds,
        watchCollectionMilliseconds: watchCollectionMilliseconds,
        initialBuild: initialResult,
        incrementalBuild: lastIncremental,
        incrementalBuilds: incrementalResults,
      );
    } finally {
      await rustClient?.close();
      await resultSubscription?.cancel();
      await scheduler.close();
      await buildSeries.close();
    }
  }

  Future<RustDaemonSession> _prepareRustSession(
    String? rustDaemonDirectory,
  ) async {
    if (rustDaemonDirectory == null || rustDaemonDirectory.isEmpty) {
      throw StateError(
        'Rust watch alpha requested, but no rust daemon directory was provided.',
      );
    }
    final client = await RustDaemonSession.start(
      daemonDirectory: rustDaemonDirectory,
    );
    final ping = await client.ping(id: 'watch-alpha-ping');
    if (ping is RustDaemonErrorResponse) {
      await client.close();
      throw StateError('Rust daemon ping failed: ${ping.message}');
    }
    return client;
  }

  Future<_CollectedWatchBatch> _collectWatchBatch({
    required String sourceEngine,
    required RustDaemonSession? rustClient,
    required String packageName,
    required String sourceFileRelativePath,
    required String generatedEntrypointPath,
    required bool mutateBuildScriptBeforeIncremental,
    required int cycleIndex,
  }) {
    switch (sourceEngine) {
      case 'rust':
        return _collectRustWatchBatch(
          rustClient: rustClient,
          packageName: packageName,
          sourceFileRelativePath: sourceFileRelativePath,
          generatedEntrypointPath: generatedEntrypointPath,
          mutateBuildScriptBeforeIncremental:
              mutateBuildScriptBeforeIncremental,
          cycleIndex: cycleIndex,
        );
      case 'dart':
      default:
        return _collectDartWatchBatch(
          packageName: packageName,
          sourceFileRelativePath: sourceFileRelativePath,
          generatedEntrypointPath: generatedEntrypointPath,
          mutateBuildScriptBeforeIncremental:
              mutateBuildScriptBeforeIncremental,
          cycleIndex: cycleIndex,
        );
    }
  }

  Future<_CollectedWatchBatch> _collectDartWatchBatch({
    required String packageName,
    required String sourceFileRelativePath,
    required String generatedEntrypointPath,
    required bool mutateBuildScriptBeforeIncremental,
    required int cycleIndex,
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
        cycleIndex: cycleIndex,
      );

      final watchBatch = await batchCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'Timed out waiting for a watcher batch for $sourceFileRelativePath on cycle ${cycleIndex + 1}.',
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
    required RustDaemonSession? rustClient,
    required String packageName,
    required String sourceFileRelativePath,
    required String generatedEntrypointPath,
    required bool mutateBuildScriptBeforeIncremental,
    required int cycleIndex,
  }) async {
    if (rustClient == null) {
      throw StateError(
        'Rust watch alpha requested, but no prepared rust client was available.',
      );
    }

    final watchId = 'watch-alpha-${cycleIndex + 1}';
    final readyResponse = await rustClient.startWatch(
      id: 'watch-alpha-start-${cycleIndex + 1}',
      watchId: watchId,
      path: Directory.current.path,
      trackedPaths: _trackedWatchPaths(
        sourceFileRelativePath: sourceFileRelativePath,
        generatedEntrypointPath: generatedEntrypointPath,
      ),
      warmupMs: 250,
    );
    if (readyResponse is RustDaemonErrorResponse) {
      throw StateError('Rust daemon startWatch failed: ${readyResponse.message}');
    }
    if (readyResponse is! RustDaemonWatchReadyResponse) {
      throw StateError(
        'Rust daemon returned an unexpected startWatch response type: ${readyResponse.runtimeType}',
      );
    }
    await _performWatchMutation(
      sourceFileRelativePath: sourceFileRelativePath,
      generatedEntrypointPath: generatedEntrypointPath,
      mutateBuildScriptBeforeIncremental: mutateBuildScriptBeforeIncremental,
      cycleIndex: cycleIndex,
    );

    final response = await rustClient.finishWatch(
      id: 'watch-alpha-finish-${cycleIndex + 1}',
      watchId: watchId,
      debounceMs: 350,
      timeoutMs: 15000,
    );
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
    required int cycleIndex,
  }) async {
    await _mutateFixtureSource(sourceFileRelativePath, cycleIndex);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _appendSourceBurstComment(sourceFileRelativePath, cycleIndex);
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
      final relativePath = _relativePath(change.path);
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

  Map<AssetId, ChangeType> _maybeDropExpectedSourceUpdate({
    required Map<AssetId, ChangeType> updates,
    required AssetId expectedSourceAssetId,
    required bool simulateDrop,
  }) {
    if (!simulateDrop || !updates.containsKey(expectedSourceAssetId)) {
      return updates;
    }
    final mutated = Map<AssetId, ChangeType>.from(updates);
    mutated.remove(expectedSourceAssetId);
    return mutated;
  }

  List<String> _trackedWatchPaths({
    required String sourceFileRelativePath,
    required String generatedEntrypointPath,
  }) {
    return [
      p.join(Directory.current.path, sourceFileRelativePath),
      p.join(Directory.current.path, 'build.yaml'),
      generatedEntrypointPath,
    ];
  }

  FastBuildStepResult _stepResult({
    required String name,
    required int elapsedMilliseconds,
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
      elapsedMilliseconds: elapsedMilliseconds,
      status: buildResult.status.name,
      failureType: _failureType(buildResult),
      outputs: buildResult.outputs.map((assetId) => '$assetId').toList(),
      errors: buildResult.errors.toList(),
      generatedFileExists: generatedFile.existsSync(),
      generatedFileHasMutation:
          generatedContent.contains('nickname') ||
          generatedContent.contains('country') ||
          generatedContent.contains('isVerified'),
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

  Future<void> _appendSourceBurstComment(
    String sourceFileRelativePath,
    int cycleIndex,
  ) async {
    final file = File(p.join(Directory.current.path, sourceFileRelativePath));
    final original = file.readAsStringSync();
    final marker =
        '// fast_build_runner watch alpha burst marker ${cycleIndex + 1}';
    if (original.contains(marker)) {
      return;
    }
    file.writeAsStringSync('$original\n$marker\n');
  }

  Future<void> _mutateFixtureSource(
    String sourceFileRelativePath,
    int cycleIndex,
  ) async {
    final file = File(p.join(Directory.current.path, sourceFileRelativePath));
    final original = file.readAsStringSync();
    final updated = switch (cycleIndex) {
      0 => _applyFieldMutation(
        original: original,
        existingConstructorFragment: 'required this.name, this.age',
        newConstructorFragment: 'required this.name, this.age, this.nickname',
        existingFieldMarker: '  final int? age;',
        newFieldLine: '  final String? nickname;',
      ),
      1 => _applyFieldMutation(
        original: original,
        existingConstructorFragment:
            'required this.name, this.age, this.nickname',
        newConstructorFragment:
            'required this.name, this.age, this.nickname, this.country',
        existingFieldMarker: '  final String? nickname;',
        newFieldLine: '  final String? country;',
      ),
      2 => _applyFieldMutation(
        original: original,
        existingConstructorFragment:
            'required this.name, this.age, this.nickname, this.country',
        newConstructorFragment:
            'required this.name, this.age, this.nickname, this.country, this.isVerified',
        existingFieldMarker: '  final String? country;',
        newFieldLine: '  final bool? isVerified;',
      ),
      _ => throw StateError(
        'Watch alpha supports at most 3 incremental fixture mutation cycles right now.',
      ),
    };
    file.writeAsStringSync(updated);
  }

  String _applyFieldMutation({
    required String original,
    required String existingConstructorFragment,
    required String newConstructorFragment,
    required String existingFieldMarker,
    required String newFieldLine,
  }) {
    if (original.contains(newFieldLine)) {
      return original;
    }
    if (!original.contains(existingConstructorFragment) ||
        !original.contains(existingFieldMarker)) {
      throw StateError(
        'Mutation markers not found in watch alpha fixture source.',
      );
    }
    return original
        .replaceFirst(existingConstructorFragment, newConstructorFragment)
        .replaceFirst(
          existingFieldMarker,
          '$existingFieldMarker\n$newFieldLine',
        );
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
