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
import 'watch_alpha_result.dart';

class FastWatchAlphaSession {
  final BuilderFactories builderFactories;
  final String upstreamCommit;

  const FastWatchAlphaSession({
    required this.builderFactories,
    required this.upstreamCommit,
  });

  Future<FastWatchAlphaResult> run({
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
    StreamSubscription<WatchEvent>? subscription;
    Timer? quietTimer;
    try {
      final initialBuild = await buildSeries.run({}, recentlyBootstrapped: true);
      final initialResult = _stepResult(
        name: 'initial',
        buildResult: initialBuild,
        generatedFileRelativePath: generatedFileRelativePath,
      );

      final observedEvents = <String>[];
      final pendingEvents = <WatchEvent>[];
      final batchCompleter = Completer<List<WatchEvent>>();
      final watcher = DirectoryWatcher(Directory.current.path);
      subscription = watcher.events.listen((event) {
        observedEvents.add('${event.type}:${event.path}');
        if (!_shouldTrackEvent(event, sourceFileRelativePath)) {
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

      await _mutateFixtureSource(sourceFileRelativePath);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await _appendSourceBurstComment(sourceFileRelativePath);
      if (mutateBuildScriptBeforeIncremental) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await _mutateBuildScript(generatedEntrypointPath);
      }

      final watchBatch = await batchCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'Timed out waiting for a watcher batch for $sourceFileRelativePath.',
        ),
      );
      final mergedUpdates = _collectChanges(packageName, watchBatch);
      final sourceAssetId = AssetId(packageName, sourceFileRelativePath);

      final incrementalBuild = await buildSeries.run(
        mergedUpdates,
        recentlyBootstrapped: false,
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
        upstreamCommit: upstreamCommit,
        generatedEntrypointPath: generatedEntrypointPath,
        runDirectory: runDirectory,
        warnings:
            mutateBuildScriptBeforeIncremental
                ? const [
                  'The generated entrypoint was intentionally mutated during watch alpha to verify buildScriptChanged handling.',
                ]
                : const [],
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
          if (!mutateBuildScriptBeforeIncremental &&
              mergedUpdates.length != 1)
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
      quietTimer?.cancel();
      await subscription?.cancel();
      await buildSeries.close();
    }
  }

  bool _shouldTrackEvent(WatchEvent event, String sourceFileRelativePath) {
    final relativePath = _relativeEventPath(event);
    if (relativePath == null) {
      return false;
    }
    return relativePath == sourceFileRelativePath ||
        relativePath == 'build.yaml' ||
        relativePath.startsWith('.dart_tool/build/entrypoint/');
  }

  String? _relativeEventPath(WatchEvent event) {
    final absoluteEventPath =
        p.isAbsolute(event.path)
            ? event.path
            : p.join(Directory.current.path, event.path);
    if (!p.isWithin(Directory.current.path, absoluteEventPath) &&
        !p.equals(Directory.current.path, absoluteEventPath)) {
      return null;
    }
    return p.relative(absoluteEventPath, from: Directory.current.path);
  }

  Map<AssetId, ChangeType> _collectChanges(
    String packageName,
    List<WatchEvent> changes,
  ) {
    final changeMap = <AssetId, ChangeType>{};
    for (final change in changes) {
      final relativePath = _relativeEventPath(change);
      if (relativePath == null) {
        continue;
      }
      final id = AssetId(packageName, relativePath);
      final originalChangeType = changeMap[id];
      if (originalChangeType != null) {
        switch (originalChangeType) {
          case ChangeType.ADD:
            if (change.type == ChangeType.REMOVE) {
              changeMap.remove(id);
            }
            break;
          case ChangeType.REMOVE:
            if (change.type == ChangeType.ADD) {
              changeMap[id] = ChangeType.MODIFY;
            } else if (change.type == ChangeType.MODIFY) {
              throw StateError(
                'Internal watch alpha error: got REMOVE followed by MODIFY for $id.',
              );
            }
            break;
          case ChangeType.MODIFY:
            if (change.type == ChangeType.REMOVE) {
              changeMap[id] = change.type;
            } else if (change.type == ChangeType.ADD) {
              throw StateError(
                'Internal watch alpha error: got MODIFY followed by ADD for $id.',
              );
            }
            break;
        }
      } else {
        changeMap[id] = change.type;
      }
    }
    return changeMap;
  }

  FastBuildStepResult _stepResult({
    required String name,
    required BuildResult buildResult,
    required String generatedFileRelativePath,
  }) {
    final generatedFile = File(
      p.join(Directory.current.path, generatedFileRelativePath),
    );
    final generatedContent =
        generatedFile.existsSync() ? generatedFile.readAsStringSync() : '';
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
    if (original.contains('// fast_build_runner watch alpha mutated build script marker')) {
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
    if (!original.contains(constructorMarker) || !original.contains(fieldMarker)) {
      throw StateError('Mutation markers not found in watch alpha fixture source.');
    }
    final updated =
        original
            .replaceFirst(
              constructorMarker,
              '  const Person({required this.name, this.age, this.nickname});',
            )
            .replaceFirst(
              fieldMarker,
              '$fieldMarker\n  final String? nickname;',
            );
    file.writeAsStringSync(updated);
  }
}
