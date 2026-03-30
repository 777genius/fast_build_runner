// ignore_for_file: implementation_imports

import 'dart:io';

import 'package:build/build.dart';
import 'package:build_runner/src/internal.dart';
import 'package:built_collection/built_collection.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'bootstrap_spike_result.dart';

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
  }) async {
    final buildPlan = await BuildPlan.load(
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
      return FastBootstrapSpikeResult(
        status: 'deferred',
        upstreamCommit: upstreamCommit,
        generatedEntrypointPath: generatedEntrypointPath,
        runDirectory: runDirectory,
        warnings: const [
          'BuildPlan reported restartIsNeeded. Full bootstrap freshness parity is deferred in this spike.',
        ],
        errors: const [],
        initialBuild: null,
        incrementalBuild: null,
      );
    }

    final buildSeries = BuildSeries(buildPlan);
    try {
      final initialBuild = await buildSeries.run({}, recentlyBootstrapped: true);
      final initialResult = _stepResult(
        name: 'initial',
        buildResult: initialBuild,
        generatedFileRelativePath: generatedFileRelativePath,
      );

      await _mutateFixtureSource(sourceFileRelativePath);

      final incrementalBuild = await buildSeries.run({
        AssetId(packageName, sourceFileRelativePath): ChangeType.MODIFY,
      }, recentlyBootstrapped: false);
      final incrementalResult = _stepResult(
        name: 'incremental',
        buildResult: incrementalBuild,
        generatedFileRelativePath: generatedFileRelativePath,
      );

      final success =
          initialBuild.status == BuildStatus.success &&
          incrementalBuild.status == BuildStatus.success &&
          incrementalResult.generatedFileExists &&
          incrementalResult.generatedFileHasMutation;

      return FastBootstrapSpikeResult(
        status: success ? 'success' : 'failure',
        upstreamCommit: upstreamCommit,
        generatedEntrypointPath: generatedEntrypointPath,
        runDirectory: runDirectory,
        warnings: const [
          'Subsequent build-script freshness parity is intentionally deferred because the custom child path does not set upstream ChildProcess.isRunning.',
        ],
        errors: [
          ...initialResult.errors,
          ...incrementalResult.errors,
          if (!incrementalResult.generatedFileHasMutation)
            'Incremental build finished without the expected generated output mutation.',
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
    required BuildResult buildResult,
    required String generatedFileRelativePath,
  }) {
    final generatedFile = File(p.join(Directory.current.path, generatedFileRelativePath));
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
    if (failureType == null) return null;
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
      throw StateError('Mutation markers not found in fixture source.');
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
