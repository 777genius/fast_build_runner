// ignore_for_file: implementation_imports

import 'dart:io';

import 'package:build/build.dart';
import 'package:built_collection/built_collection.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'bootstrap_spike_result.dart';
import 'fast_build_plan.dart';
import 'fast_build_run_profile.dart';
import 'fast_build_series.dart';
import 'package:build_runner/src/internal.dart';

class FastSpikeSession {
  final BuilderFactories builderFactories;
  final String upstreamCommit;

  const FastSpikeSession({
    required this.builderFactories,
    required this.upstreamCommit,
  });

  Future<FastBootstrapSpikeResult> run({
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
        trackPerformance: true,
        verbose: false,
        verboseDurations: false,
        workspace: false,
      ),
      testingOverrides: const TestingOverrides(),
      recentlyBootstrapped: true,
    );

    await buildPlan.deleteFilesAndFolders();
    if (buildPlan.restartIsNeeded) {
      return FastBootstrapSpikeResult(
        status: 'deferred',
        upstreamCommit: upstreamCommit,
        generatedEntrypointPath: generatedEntrypointPath,
        runDirectory: runDirectory,
        warnings: const [
          'FastBuildPlan reported restartIsNeeded during bootstrap load. Full restart parity remains deferred for this path.',
        ],
        errors: const [],
        initialBuild: null,
        incrementalBuild: null,
      );
    }

    final buildSeries = FastBuildSeries(buildPlan);
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
        buildResult: initialBuild.result,
        buildProfile: initialBuild.profile,
        generatedFileRelativePath: generatedFileRelativePath,
      );

      await _mutateFixtureSource(sourceFileRelativePath);
      if (mutateBuildScriptBeforeIncremental) {
        await _mutateBuildScript(generatedEntrypointPath);
      }

      final incrementalStopwatch = Stopwatch()..start();
      final incrementalBuild = await buildSeries.run({
        AssetId(packageName, sourceFileRelativePath): ChangeType.MODIFY,
      }, recentlyBootstrapped: false);
      incrementalStopwatch.stop();
      final incrementalResult = _stepResult(
        name: 'incremental',
        elapsedMilliseconds: incrementalStopwatch.elapsedMilliseconds,
        buildResult: incrementalBuild.result,
        buildProfile: incrementalBuild.profile,
        generatedFileRelativePath: generatedFileRelativePath,
      );

      final sawExpectedBuildScriptChange =
          mutateBuildScriptBeforeIncremental &&
          incrementalResult.failureType == 'buildScriptChanged';
      final sawExpectedMutation =
          !mutateBuildScriptBeforeIncremental &&
          incrementalBuild.result.status == BuildStatus.success &&
          incrementalResult.generatedFileExists &&
          incrementalResult.generatedFileHasMutation;
      final success =
          initialBuild.result.status == BuildStatus.success &&
          (sawExpectedMutation || sawExpectedBuildScriptChange);

      return FastBootstrapSpikeResult(
        status: success ? 'success' : 'failure',
        upstreamCommit: upstreamCommit,
        generatedEntrypointPath: generatedEntrypointPath,
        runDirectory: runDirectory,
        warnings: mutateBuildScriptBeforeIncremental
            ? const [
                'The generated entrypoint was intentionally mutated before the second run to verify buildScriptChanged detection.',
              ]
            : const [],
        errors: [
          ...initialResult.errors,
          ...incrementalResult.errors,
          if (!mutateBuildScriptBeforeIncremental &&
              !incrementalResult.generatedFileHasMutation)
            'Incremental build finished without the expected generated output mutation.',
          if (mutateBuildScriptBeforeIncremental &&
              incrementalResult.failureType != 'buildScriptChanged')
            'Incremental build did not surface buildScriptChanged after the generated entrypoint was mutated.',
        ],
        initialBuild: initialResult,
        incrementalBuild: incrementalResult,
      );
    } finally {
      await buildSeries.close();
    }
  }

  FastBuildStepResult _stepResult({
    required String name,
    required int elapsedMilliseconds,
    required BuildResult buildResult,
    FastBuildRunProfile? buildProfile,
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
      generatedFileHasMutation: generatedContent.contains('nickname'),
      profile: buildProfile?.toJson(),
    );
  }

  String? _failureType(BuildResult buildResult) {
    final failureType = buildResult.failureType;
    if (failureType == null) return null;
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
    if (original.contains('// fast_build_runner mutated build script marker')) {
      return;
    }
    file.writeAsStringSync(
      '$original\n// fast_build_runner mutated build script marker\n',
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
      throw StateError('Mutation markers not found in fixture source.');
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
