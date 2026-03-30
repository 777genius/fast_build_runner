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

const _dartWatchDebounceMs = 350;
const _rustWatchDebounceMs = 200;
const _watchTimeout = Duration(seconds: 15);

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
    required int noiseFilesPerCycle,
    required bool continuousScheduling,
    required int settleBuildDelayMs,
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
    final buildResults = <FastWatchScheduledBuild<BuildResult>>[];
    final scheduler = FastWatchScheduler<BuildResult>(
      onBuild: (updates) =>
          buildSeries.run(updates, recentlyBootstrapped: false),
      postBuildSettleDelay: Duration(milliseconds: settleBuildDelayMs),
    );
    final sourceAssetId = AssetId(packageName, sourceFileRelativePath);
    RustDaemonSession? rustClient;
    _PersistentDartWatchCollector? dartWatchCollector;
    String? rustWatchId;
    int? rustDaemonStartupMilliseconds;
    StreamSubscription<FastWatchScheduledBuild<BuildResult>>?
    resultSubscription;

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
        rustDaemonStartupMilliseconds =
            rustStartupStopwatch.elapsedMilliseconds;
        rustWatchId = 'watch-alpha-session';
        final readyResponse = await rustClient.startWatch(
          id: 'watch-alpha-start',
          watchId: rustWatchId,
          path: Directory.current.path,
          trackedPaths: _trackedWatchPaths(
            sourceFileRelativePath: sourceFileRelativePath,
            generatedEntrypointPath: generatedEntrypointPath,
          ),
          warmupMs: 125,
        );
        if (readyResponse is RustDaemonErrorResponse) {
          throw StateError(
            'Rust daemon startWatch failed: ${readyResponse.message}',
          );
        }
        if (readyResponse is! RustDaemonWatchReadyResponse) {
          throw StateError(
            'Rust daemon returned an unexpected startWatch response type: ${readyResponse.runtimeType}',
          );
        }
      } else {
        dartWatchCollector = await _PersistentDartWatchCollector.start(
          rootPath: Directory.current.path,
          sourceFileRelativePath: sourceFileRelativePath,
        );
      }
      final observedEventBatches = <List<String>>[];
      final mergedUpdateBatches = <List<String>>[];
      final watchCollectionMilliseconds = <int>[];
      final incrementalResults = <FastBuildStepResult>[];
      final resolutionWarnings = <String>[];
      var submittedBuildBatches = 0;
      _CollectedWatchBatch? lastWatchBatch;

      for (var cycleIndex = 0; cycleIndex < incrementalCycles; cycleIndex++) {
        final watchCollectionStopwatch = Stopwatch()..start();
        final watchBatch = await _collectWatchBatch(
          sourceEngine: sourceEngine,
          dartWatchCollector: dartWatchCollector,
          rustClient: rustClient,
          rustWatchId: rustWatchId,
          packageName: packageName,
          sourceFileRelativePath: sourceFileRelativePath,
          generatedEntrypointPath: generatedEntrypointPath,
          noiseFilesPerCycle: noiseFilesPerCycle,
          keepAlive: cycleIndex + 1 < incrementalCycles,
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
        if (mergedUpdates.isNotEmpty) {
          submittedBuildBatches++;
        }
        if (continuousScheduling) {
          unawaited(scheduler.enqueue(mergedUpdates));
        } else {
          final expectedBuildCount = buildResults.length + 1;
          await scheduler.enqueue(mergedUpdates);
          if (mergedUpdates.isNotEmpty &&
              buildResults.length < expectedBuildCount) {
            throw StateError(
              'Watch alpha scheduler became idle without producing build #$expectedBuildCount.',
            );
          }
          if (mergedUpdates.isNotEmpty) {
            final scheduledBuild = buildResults[expectedBuildCount - 1];
            incrementalResults.add(
              _stepResult(
                name: 'incremental-${cycleIndex + 1}',
                elapsedMilliseconds: scheduledBuild.elapsedMilliseconds,
                buildResult: scheduledBuild.result,
                generatedFileRelativePath: generatedFileRelativePath,
              ),
            );
          }
        }
      }

      if (continuousScheduling) {
        await scheduler.waitForIdle();
        for (
          var buildIndex = 0;
          buildIndex < buildResults.length;
          buildIndex++
        ) {
          final scheduledBuild = buildResults[buildIndex];
          incrementalResults.add(
            _stepResult(
              name: 'incremental-${buildIndex + 1}',
              elapsedMilliseconds: scheduledBuild.elapsedMilliseconds,
              buildResult: scheduledBuild.result,
              generatedFileRelativePath: generatedFileRelativePath,
            ),
          );
        }
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
          if (continuousScheduling)
            'Watch alpha kept collecting watch batches while builds were in flight.',
          if (settleBuildDelayMs > 0)
            'Watch alpha used a post-build settle window of ${settleBuildDelayMs}ms to coalesce bursty updates.',
          if (noiseFilesPerCycle > 0)
            'Watch alpha injected $noiseFilesPerCycle unrelated noise file(s) on every incremental cycle.',
          if (continuousScheduling &&
              buildResults.length < submittedBuildBatches)
            'Watch alpha coalesced $submittedBuildBatches submitted update batch(es) into ${buildResults.length} build run(s).',
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
              submittedBuildBatches > 0 &&
              incrementalResults.isEmpty)
            'Watch alpha submitted non-empty update batches but no incremental builds were observed.',
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
      await dartWatchCollector?.close();
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
    required _PersistentDartWatchCollector? dartWatchCollector,
    required RustDaemonSession? rustClient,
    required String? rustWatchId,
    required String packageName,
    required String sourceFileRelativePath,
    required String generatedEntrypointPath,
    required int noiseFilesPerCycle,
    required bool keepAlive,
    required bool mutateBuildScriptBeforeIncremental,
    required int cycleIndex,
  }) {
    switch (sourceEngine) {
      case 'rust':
        return _collectRustWatchBatch(
          rustClient: rustClient,
          rustWatchId: rustWatchId,
          packageName: packageName,
          sourceFileRelativePath: sourceFileRelativePath,
          generatedEntrypointPath: generatedEntrypointPath,
          noiseFilesPerCycle: noiseFilesPerCycle,
          keepAlive: keepAlive,
          mutateBuildScriptBeforeIncremental:
              mutateBuildScriptBeforeIncremental,
          cycleIndex: cycleIndex,
        );
      case 'dart':
      default:
        return _collectDartWatchBatch(
          dartWatchCollector: dartWatchCollector,
          packageName: packageName,
          sourceFileRelativePath: sourceFileRelativePath,
          generatedEntrypointPath: generatedEntrypointPath,
          noiseFilesPerCycle: noiseFilesPerCycle,
          mutateBuildScriptBeforeIncremental:
              mutateBuildScriptBeforeIncremental,
          cycleIndex: cycleIndex,
        );
    }
  }

  Future<_CollectedWatchBatch> _collectDartWatchBatch({
    required _PersistentDartWatchCollector? dartWatchCollector,
    required String packageName,
    required String sourceFileRelativePath,
    required String generatedEntrypointPath,
    required int noiseFilesPerCycle,
    required bool mutateBuildScriptBeforeIncremental,
    required int cycleIndex,
  }) async {
    if (dartWatchCollector == null) {
      throw StateError(
        'Dart watch alpha requested, but no persistent dart watch collector was available.',
      );
    }

    final watchBatch = await dartWatchCollector.collectNextBatch(
      mutate: () => _performWatchMutation(
        sourceFileRelativePath: sourceFileRelativePath,
        generatedEntrypointPath: generatedEntrypointPath,
        noiseFilesPerCycle: noiseFilesPerCycle,
        mutateBuildScriptBeforeIncremental: mutateBuildScriptBeforeIncremental,
        cycleIndex: cycleIndex,
      ),
    );
    return _CollectedWatchBatch(
      observedEvents: watchBatch.observedEvents,
      mergedUpdates: _collectDartChanges(packageName, watchBatch.watchEvents),
      isEmpty: watchBatch.watchEvents.isEmpty,
    );
  }

  Future<_CollectedWatchBatch> _collectRustWatchBatch({
    required RustDaemonSession? rustClient,
    required String? rustWatchId,
    required String packageName,
    required String sourceFileRelativePath,
    required String generatedEntrypointPath,
    required int noiseFilesPerCycle,
    required bool keepAlive,
    required bool mutateBuildScriptBeforeIncremental,
    required int cycleIndex,
  }) async {
    if (rustClient == null) {
      throw StateError(
        'Rust watch alpha requested, but no prepared rust client was available.',
      );
    }
    if (rustWatchId == null || rustWatchId.isEmpty) {
      throw StateError(
        'Rust watch alpha requested, but no active rust watch id was available.',
      );
    }
    await _performWatchMutation(
      sourceFileRelativePath: sourceFileRelativePath,
      generatedEntrypointPath: generatedEntrypointPath,
      noiseFilesPerCycle: noiseFilesPerCycle,
      mutateBuildScriptBeforeIncremental: mutateBuildScriptBeforeIncremental,
      cycleIndex: cycleIndex,
    );

    final response = await rustClient.finishWatch(
      id: 'watch-alpha-finish-${cycleIndex + 1}',
      watchId: rustWatchId,
      debounceMs: _rustWatchDebounceMs,
      timeoutMs: 15000,
      keepAlive: keepAlive,
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
    required int noiseFilesPerCycle,
    required bool mutateBuildScriptBeforeIncremental,
    required int cycleIndex,
  }) async {
    await _mutateFixtureSource(sourceFileRelativePath, cycleIndex);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _appendSourceBurstComment(sourceFileRelativePath, cycleIndex);
    if (noiseFilesPerCycle > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await _mutateNoiseFiles(cycleIndex, noiseFilesPerCycle);
    }
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
      generatedFileHasMutation: RegExp(
        r'(nickname|country|isVerified|extraField\d+)',
      ).hasMatch(generatedContent),
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

  Future<void> _mutateNoiseFiles(int cycleIndex, int noiseFilesPerCycle) async {
    final noiseDirectory = Directory(
      p.join(Directory.current.path, '.dart_tool', 'fast_build_runner_noise'),
    )..createSync(recursive: true);
    for (var noiseIndex = 0; noiseIndex < noiseFilesPerCycle; noiseIndex++) {
      final file = File(
        p.join(
          noiseDirectory.path,
          'noise_${cycleIndex + 1}_${noiseIndex + 1}.txt',
        ),
      );
      file.writeAsStringSync(
        'cycle=${cycleIndex + 1}\nnoise=${noiseIndex + 1}\n'
        'timestamp=${DateTime.now().microsecondsSinceEpoch}\n',
      );
    }
  }

  Future<void> _mutateFixtureSource(
    String sourceFileRelativePath,
    int cycleIndex,
  ) async {
    final file = File(p.join(Directory.current.path, sourceFileRelativePath));
    final original = file.readAsStringSync();
    final field = _fieldForCycle(cycleIndex);
    final updated = _applyFieldMutation(
      original: original,
      fieldName: field.name,
      fieldType: field.type,
    );
    file.writeAsStringSync(updated);
  }

  String _applyFieldMutation({
    required String original,
    required String fieldName,
    required String fieldType,
  }) {
    final newFieldLine = '  final $fieldType $fieldName;';
    if (original.contains(newFieldLine)) {
      return original;
    }
    const constructorSuffix = '});';
    const factoryMarker = '  factory Person.fromJson';
    if (!original.contains(constructorSuffix) ||
        !original.contains(factoryMarker)) {
      throw StateError(
        'Mutation markers not found in watch alpha fixture source.',
      );
    }
    return original
        .replaceFirst(constructorSuffix, ', this.$fieldName$constructorSuffix')
        .replaceFirst(factoryMarker, '$newFieldLine\n\n$factoryMarker');
  }

  _FieldMutation _fieldForCycle(int cycleIndex) {
    return switch (cycleIndex) {
      0 => const _FieldMutation(name: 'nickname', type: 'String?'),
      1 => const _FieldMutation(name: 'country', type: 'String?'),
      2 => const _FieldMutation(name: 'isVerified', type: 'bool?'),
      _ => _FieldMutation(
        name: 'extraField${cycleIndex + 1}',
        type: cycleIndex.isEven ? 'String?' : 'int?',
      ),
    };
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

class _FieldMutation {
  final String name;
  final String type;

  const _FieldMutation({required this.name, required this.type});
}

class _PersistentDartWatchCollector {
  final String rootPath;
  final String sourceFileRelativePath;
  final StreamSubscription<WatchEvent> _subscription;

  Timer? _quietTimer;
  Completer<_DartWatchBatch>? _batchCompleter;
  final List<String> _observedEvents = [];
  final List<WatchEvent> _pendingEvents = [];

  _PersistentDartWatchCollector._({
    required this.rootPath,
    required this.sourceFileRelativePath,
    required StreamSubscription<WatchEvent> subscription,
  }) : _subscription = subscription;

  static Future<_PersistentDartWatchCollector> start({
    required String rootPath,
    required String sourceFileRelativePath,
  }) async {
    final watcher = DirectoryWatcher(rootPath);
    late final _PersistentDartWatchCollector collector;
    final subscription = watcher.events.listen((event) {
      collector._onEvent(event);
    });
    collector = _PersistentDartWatchCollector._(
      rootPath: rootPath,
      sourceFileRelativePath: sourceFileRelativePath,
      subscription: subscription,
    );
    await watcher.ready;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return collector;
  }

  Future<_DartWatchBatch> collectNextBatch({
    required Future<void> Function() mutate,
  }) async {
    if (_batchCompleter != null) {
      throw StateError('A dart watch batch is already active.');
    }
    _observedEvents.clear();
    _pendingEvents.clear();
    _batchCompleter = Completer<_DartWatchBatch>();
    await mutate();
    try {
      return await _batchCompleter!.future.timeout(
        _watchTimeout,
        onTimeout: () => throw TimeoutException(
          'Timed out waiting for a persistent dart watcher batch for $sourceFileRelativePath.',
        ),
      );
    } finally {
      _quietTimer?.cancel();
      _quietTimer = null;
      _batchCompleter = null;
    }
  }

  Future<void> close() async {
    _quietTimer?.cancel();
    await _subscription.cancel();
  }

  void _onEvent(WatchEvent event) {
    final batchCompleter = _batchCompleter;
    if (batchCompleter == null || batchCompleter.isCompleted) {
      return;
    }

    _observedEvents.add('${event.type}:${event.path}');
    _quietTimer?.cancel();
    _quietTimer = Timer(const Duration(milliseconds: _dartWatchDebounceMs), () {
      if (batchCompleter.isCompleted) {
        return;
      }
      batchCompleter.complete(
        _DartWatchBatch(
          observedEvents: List<String>.from(_observedEvents),
          watchEvents: List<WatchEvent>.from(_pendingEvents),
        ),
      );
    });

    final relativePath = _relativePathFromRoot(rootPath, event.path);
    if (!_shouldTrackRelativePath(relativePath, sourceFileRelativePath)) {
      return;
    }
    _pendingEvents.add(event);
  }

  static String? _relativePathFromRoot(String rootPath, String path) {
    final absolutePath = p.isAbsolute(path) ? path : p.join(rootPath, path);
    if (!p.isWithin(rootPath, absolutePath) &&
        !p.equals(rootPath, absolutePath)) {
      return null;
    }
    return p.relative(absolutePath, from: rootPath);
  }

  static bool _shouldTrackRelativePath(
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
}

class _DartWatchBatch {
  final List<String> observedEvents;
  final List<WatchEvent> watchEvents;

  const _DartWatchBatch({
    required this.observedEvents,
    required this.watchEvents,
  });
}
