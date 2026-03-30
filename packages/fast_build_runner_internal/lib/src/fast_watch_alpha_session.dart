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
        initialBuild: null,
        incrementalBuild: null,
      );
    }

    final buildSeries = FastBuildSeries(buildPlan);
    StreamSubscription<WatchEvent>? subscription;
    try {
      final initialBuild = await buildSeries.run({}, recentlyBootstrapped: true);
      final initialResult = _stepResult(
        name: 'initial',
        buildResult: initialBuild,
        generatedFileRelativePath: generatedFileRelativePath,
      );

      final observedEvents = <String>[];
      final sourceFilePath = p.join(Directory.current.path, sourceFileRelativePath);
      final eventCompleter = Completer<WatchEvent>();
      final watcher = DirectoryWatcher(Directory.current.path);
      subscription = watcher.events.listen((event) {
        observedEvents.add('${event.type}:${event.path}');
        final absoluteEventPath =
            p.isAbsolute(event.path) ? event.path : p.join(Directory.current.path, event.path);
        if (!p.equals(p.normalize(absoluteEventPath), p.normalize(sourceFilePath))) {
          return;
        }
        if (!eventCompleter.isCompleted) {
          eventCompleter.complete(event);
        }
      });
      await watcher.ready;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await _mutateFixtureSource(sourceFileRelativePath);
      final watchEvent = await eventCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'Timed out waiting for a watcher event for $sourceFileRelativePath.',
        ),
      );

      final incrementalBuild = await buildSeries.run({
        AssetId(packageName, sourceFileRelativePath): watchEvent.type,
      }, recentlyBootstrapped: false);
      final incrementalResult = _stepResult(
        name: 'incremental',
        buildResult: incrementalBuild,
        generatedFileRelativePath: generatedFileRelativePath,
      );

      final success =
          initialBuild.status == BuildStatus.success &&
          incrementalBuild.status == BuildStatus.success &&
          incrementalResult.generatedFileHasMutation;

      return FastWatchAlphaResult(
        status: success ? 'success' : 'failure',
        upstreamCommit: upstreamCommit,
        generatedEntrypointPath: generatedEntrypointPath,
        runDirectory: runDirectory,
        warnings: const [],
        errors: [
          ...initialResult.errors,
          ...incrementalResult.errors,
          if (observedEvents.isEmpty)
            'Watch alpha completed without observing any filesystem events.',
          if (!incrementalResult.generatedFileHasMutation)
            'Watch alpha incremental rebuild finished without the expected generated output mutation.',
        ],
        observedEvents: observedEvents,
        initialBuild: initialResult,
        incrementalBuild: incrementalResult,
      );
    } finally {
      await subscription?.cancel();
      await buildSeries.close();
    }
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
