// ignore_for_file: implementation_imports

import 'dart:io';

import 'package:build/build.dart';
import 'package:build/experiments.dart';
import 'package:build_runner/src/build/asset_graph/exceptions.dart';
import 'package:build_runner/src/build/asset_graph/graph.dart';
import 'package:build_runner/src/exceptions.dart';
import 'package:build_runner/src/io/asset_tracker.dart';
import 'package:build_runner/src/internal.dart';
import 'package:built_collection/built_collection.dart';
import 'package:watcher/watcher.dart';
import 'package:build_runner/src/build_plan/build_phase_creator.dart';

import 'fast_bootstrapper.dart';

class FastBuildPlan extends BuildPlan {
  FastBuildPlan({
    required super.builderFactories,
    required super.buildOptions,
    required super.testingOverrides,
    required super.buildPackages,
    required super.readerWriter,
    required super.buildConfigs,
    required super.buildPhases,
    required super.previousAssetGraph,
    required super.previousAssetGraphWasTaken,
    required super.restartIsNeeded,
    required FastBootstrapper super.bootstrapper,
    required super.assetGraph,
    required super.assetGraphWasTaken,
    required super.updates,
    required super.filesToDelete,
    required super.foldersToDelete,
  });

  @override
  FastBootstrapper get bootstrapper => super.bootstrapper as FastBootstrapper;

  static Future<FastBuildPlan> load({
    required BuilderFactories builderFactories,
    required BuildOptions buildOptions,
    required TestingOverrides testingOverrides,
    FastBootstrapper? bootstrapper,
    bool recentlyBootstrapped = true,
  }) async {
    final resolvedBootstrapper =
        bootstrapper ??
        FastBootstrapper(
          workspace: buildOptions.workspace,
          compileAot: buildOptions.forceAot,
        );
    var restartIsNeeded = false;
    final kernelFreshness = await resolvedBootstrapper.checkCompileFreshness(
      digestsAreFresh: recentlyBootstrapped,
    );
    if (!kernelFreshness.outputIsFresh) {
      restartIsNeeded = true;
    }

    final buildPackages =
        testingOverrides.buildPackages ??
        await BuildPackages.forThisPackage(workspace: buildOptions.workspace);
    final readerWriter =
        testingOverrides.readerWriter ?? ReaderWriter(buildPackages);
    final buildConfigs = await BuildConfigs.load(
      readerWriter: readerWriter,
      buildPackages: buildPackages,
      testingOverrides: testingOverrides,
      configKey: buildOptions.configKey,
    );

    var builderDefinitions =
        testingOverrides.builderDefinitions ??
        await AbstractBuilderDefinition.load(
          buildPackages: buildPackages,
          readerWriter: readerWriter,
        );
    if (!builderFactories.hasFactoriesFor(builderDefinitions)) {
      restartIsNeeded = true;
      builderDefinitions = BuiltList();
    }

    final buildPhases =
        testingOverrides.buildPhases ??
        await BuildPhaseCreator(
          builderFactories: builderFactories,
          buildPackages: buildPackages,
          buildConfigs: buildConfigs,
          builderDefinitions: builderDefinitions,
          builderConfigOverrides: buildOptions.builderConfigOverrides,
          isReleaseBuild: buildOptions.isReleaseBuild,
          workspace: buildOptions.workspace,
        ).createBuildPhases();
    buildPhases.checkOutputLocations(buildPackages.outputPackages);

    AssetGraph? previousAssetGraph;
    final filesToDelete = <AssetId>{};
    final foldersToDelete = <AssetId>{};
    final assetGraphId = AssetId(buildPackages.outputRoot, assetGraphPath);
    final generatedOutputDirectoryId = AssetId(
      buildPackages.outputRoot,
      generatedOutputDirectory,
    );

    if (await readerWriter.canRead(assetGraphId)) {
      previousAssetGraph = AssetGraph.deserialize(
        await readerWriter.readAsBytes(assetGraphId),
      );
      if (previousAssetGraph != null) {
        final buildPhasesChanged =
            buildPhases.digest != previousAssetGraph.buildPhasesDigest;
        final pkgVersionsChanged =
            previousAssetGraph.packageLanguageVersions !=
            buildPackages.languageVersions;
        final enabledExperimentsChanged =
            previousAssetGraph.enabledExperiments != enabledExperiments.build();
        if (buildPhasesChanged ||
            pkgVersionsChanged ||
            enabledExperimentsChanged ||
            !isSameSdkVersion(
              previousAssetGraph.dartVersion,
              Platform.version,
            ) ||
            restartIsNeeded ||
            previousAssetGraph.kernelDigest != kernelFreshness.digest) {
          filesToDelete.addAll(
            previousAssetGraph.outputsToDelete(buildPackages),
          );
          previousAssetGraph = null;
        }
      }
    }

    if (previousAssetGraph == null) {
      filesToDelete.add(assetGraphId);
      foldersToDelete.add(generatedOutputDirectoryId);
    }

    final assetTracker = AssetTracker(
      readerWriter,
      buildPackages,
      buildConfigs,
    );
    final inputSources = await assetTracker.findInputSources();
    final cacheDirSources = await assetTracker.findCacheDirSources();

    AssetGraph? assetGraph;
    Map<AssetId, ChangeType>? updates;
    if (previousAssetGraph != null) {
      updates = await assetTracker.computeSourceUpdates(
        inputSources,
        cacheDirSources,
        previousAssetGraph,
      );
      assetGraph = previousAssetGraph.copyForNextBuild(buildPhases);

      if (restartIsNeeded) {
        filesToDelete.addAll(previousAssetGraph.outputsToDelete(buildPackages));
        foldersToDelete.add(generatedOutputDirectoryId);
        previousAssetGraph = null;
        filesToDelete.add(assetGraphId);
        updates = null;
      }
    }

    if (assetGraph == null) {
      inputSources.removeAll(filesToDelete);

      try {
        assetGraph = await AssetGraph.build(
          kernelDigest: kernelFreshness.digest,
          buildPhases,
          inputSources,
          buildPackages,
          readerWriter,
        );
      } on DuplicateAssetNodeException catch (e) {
        buildLog.error(e.toString());
        throw const CannotBuildException();
      }

      final conflictsInDeps = assetGraph.outputs
          .where((n) => !buildPackages.outputPackages.contains(n.package))
          .where(inputSources.contains)
          .toSet();
      if (conflictsInDeps.isNotEmpty) {
        buildLog.error(
          'There are existing files in dependencies which conflict '
          'with files that a Builder may produce. These must be removed or '
          'the Builders disabled before a build can continue: '
          '${conflictsInDeps.map((a) => a.uri).join('\n')}',
        );
        throw const CannotBuildException();
      }

      filesToDelete.addAll(
        assetGraph.outputs
            .where((n) => buildPackages.outputPackages.contains(n.package))
            .where(inputSources.contains)
            .toSet(),
      );
    }

    return FastBuildPlan(
      builderFactories: builderFactories,
      buildOptions: buildOptions,
      testingOverrides: testingOverrides,
      buildPackages: buildPackages,
      readerWriter: readerWriter,
      buildConfigs: buildConfigs,
      buildPhases: buildPhases,
      previousAssetGraph: previousAssetGraph,
      previousAssetGraphWasTaken: false,
      restartIsNeeded: restartIsNeeded,
      bootstrapper: resolvedBootstrapper,
      assetGraph: assetGraph,
      assetGraphWasTaken: false,
      updates: updates?.build(),
      filesToDelete: filesToDelete.toBuiltList(),
      foldersToDelete: foldersToDelete.toBuiltList(),
    );
  }

  @override
  FastBuildPlan copyWith({
    BuiltSet<BuildDirectory>? buildDirs,
    BuiltSet<BuildFilter>? buildFilters,
    ReaderWriter? readerWriter,
  }) => throw UnsupportedError(
    'FastBuildPlan.copyWith is intentionally unsupported in the bootstrap spike. '
    'Use FastBuildSeries, which keeps the original BuildPlan instance alive so '
    'the custom bootstrapper and asset graph ownership remain correct.',
  );

  @override
  Future<FastBuildPlan> reload() => FastBuildPlan.load(
    builderFactories: builderFactories,
    buildOptions: buildOptions,
    testingOverrides: testingOverrides,
    bootstrapper: FastBootstrapper(
      workspace: buildOptions.workspace,
      compileAot: buildOptions.forceAot,
    ),
    recentlyBootstrapped: false,
  );
}
