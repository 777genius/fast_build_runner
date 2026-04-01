// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart';
import 'package:built_collection/built_collection.dart';
import 'package:crypto/crypto.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'package:build_runner/src/build/asset_graph/graph.dart';
import 'package:build_runner/src/build/asset_graph/node.dart';
import 'package:build_runner/src/build/asset_graph/post_process_build_step_id.dart';
import 'package:build_runner/src/build/build_dirs.dart';
import 'package:build_runner/src/build/build_result.dart';
import 'package:build_runner/src/build/input_tracker.dart';
import 'package:build_runner/src/build/library_cycle_graph/asset_deps_loader.dart';
import 'package:build_runner/src/build/library_cycle_graph/library_cycle_graph.dart';
import 'package:build_runner/src/build/library_cycle_graph/library_cycle_graph_loader.dart';
import 'package:build_runner/src/build/library_cycle_graph/phased_asset_deps.dart';
import 'package:build_runner/src/build/performance_tracker.dart';
import 'package:build_runner/src/build/performance_tracking_resolvers.dart';
import 'package:build_runner/src/build/resolver/analysis_driver_model.dart';
import 'package:build_runner/src/build/resolver/resolvers_impl.dart';
import 'package:build_runner/src/build/run_builder.dart';
import 'package:build_runner/src/build/run_post_process_builder.dart';
import 'package:build_runner/src/build/single_step_reader_writer.dart';
import 'package:build_runner/src/build_plan/build_configs.dart';
import 'package:build_runner/src/build_plan/build_options.dart';
import 'package:build_runner/src/build_plan/build_packages.dart';
import 'package:build_runner/src/build_plan/build_phases.dart';
import 'package:build_runner/src/build_plan/build_plan.dart';
import 'package:build_runner/src/build_plan/phase.dart';
import 'package:build_runner/src/build_plan/testing_overrides.dart';
import 'package:build_runner/src/constants.dart';
import 'package:build_runner/src/io/build_output_reader.dart';
import 'package:build_runner/src/io/create_merged_dir.dart';
import 'package:build_runner/src/io/reader_writer.dart';
import 'package:build_runner/src/logging/build_log.dart';
import 'package:build_runner/src/logging/timed_activities.dart';

final ResolversImpl _defaultResolvers = ResolversImpl(
  analysisDriverModel: AnalysisDriverModel(),
);

class FastBuildInternalMetrics {
  final int assetGraphUpdateMilliseconds;
  final int runPhasesMilliseconds;
  final int phasedAssetDepsUpdateMilliseconds;
  final int matchingPrimaryInputsMilliseconds;
  final int buildShouldRunMilliseconds;
  final int buildShouldRunInputCheckMilliseconds;
  final int buildShouldRunGraphCheckMilliseconds;
  final int buildShouldRunInputCheckCount;
  final int buildShouldRunGraphCheckCount;
  final int buildShouldRunChangedInputHits;
  final int buildShouldRunChangedGraphHits;
  final int assetGraphPersistMilliseconds;
  final int cacheFlushMilliseconds;
  final int resourceDisposeMilliseconds;
  final int mergedOutputsMilliseconds;
  final int resolverResetMilliseconds;
  final int buildLogFinishMilliseconds;

  const FastBuildInternalMetrics({
    required this.assetGraphUpdateMilliseconds,
    required this.runPhasesMilliseconds,
    required this.phasedAssetDepsUpdateMilliseconds,
    required this.matchingPrimaryInputsMilliseconds,
    required this.buildShouldRunMilliseconds,
    required this.buildShouldRunInputCheckMilliseconds,
    required this.buildShouldRunGraphCheckMilliseconds,
    required this.buildShouldRunInputCheckCount,
    required this.buildShouldRunGraphCheckCount,
    required this.buildShouldRunChangedInputHits,
    required this.buildShouldRunChangedGraphHits,
    required this.assetGraphPersistMilliseconds,
    required this.cacheFlushMilliseconds,
    required this.resourceDisposeMilliseconds,
    required this.mergedOutputsMilliseconds,
    required this.resolverResetMilliseconds,
    required this.buildLogFinishMilliseconds,
  });

  static const zero = FastBuildInternalMetrics(
    assetGraphUpdateMilliseconds: 0,
    runPhasesMilliseconds: 0,
    phasedAssetDepsUpdateMilliseconds: 0,
    matchingPrimaryInputsMilliseconds: 0,
    buildShouldRunMilliseconds: 0,
    buildShouldRunInputCheckMilliseconds: 0,
    buildShouldRunGraphCheckMilliseconds: 0,
    buildShouldRunInputCheckCount: 0,
    buildShouldRunGraphCheckCount: 0,
    buildShouldRunChangedInputHits: 0,
    buildShouldRunChangedGraphHits: 0,
    assetGraphPersistMilliseconds: 0,
    cacheFlushMilliseconds: 0,
    resourceDisposeMilliseconds: 0,
    mergedOutputsMilliseconds: 0,
    resolverResetMilliseconds: 0,
    buildLogFinishMilliseconds: 0,
  );

  FastBuildInternalMetrics copyWith({
    int? assetGraphUpdateMilliseconds,
    int? runPhasesMilliseconds,
    int? phasedAssetDepsUpdateMilliseconds,
    int? matchingPrimaryInputsMilliseconds,
    int? buildShouldRunMilliseconds,
    int? buildShouldRunInputCheckMilliseconds,
    int? buildShouldRunGraphCheckMilliseconds,
    int? buildShouldRunInputCheckCount,
    int? buildShouldRunGraphCheckCount,
    int? buildShouldRunChangedInputHits,
    int? buildShouldRunChangedGraphHits,
    int? assetGraphPersistMilliseconds,
    int? cacheFlushMilliseconds,
    int? resourceDisposeMilliseconds,
    int? mergedOutputsMilliseconds,
    int? resolverResetMilliseconds,
    int? buildLogFinishMilliseconds,
  }) {
    return FastBuildInternalMetrics(
      assetGraphUpdateMilliseconds:
          assetGraphUpdateMilliseconds ?? this.assetGraphUpdateMilliseconds,
      runPhasesMilliseconds:
          runPhasesMilliseconds ?? this.runPhasesMilliseconds,
      phasedAssetDepsUpdateMilliseconds:
          phasedAssetDepsUpdateMilliseconds ??
          this.phasedAssetDepsUpdateMilliseconds,
      matchingPrimaryInputsMilliseconds:
          matchingPrimaryInputsMilliseconds ??
          this.matchingPrimaryInputsMilliseconds,
      buildShouldRunMilliseconds:
          buildShouldRunMilliseconds ?? this.buildShouldRunMilliseconds,
      buildShouldRunInputCheckMilliseconds:
          buildShouldRunInputCheckMilliseconds ??
          this.buildShouldRunInputCheckMilliseconds,
      buildShouldRunGraphCheckMilliseconds:
          buildShouldRunGraphCheckMilliseconds ??
          this.buildShouldRunGraphCheckMilliseconds,
      buildShouldRunInputCheckCount:
          buildShouldRunInputCheckCount ?? this.buildShouldRunInputCheckCount,
      buildShouldRunGraphCheckCount:
          buildShouldRunGraphCheckCount ?? this.buildShouldRunGraphCheckCount,
      buildShouldRunChangedInputHits:
          buildShouldRunChangedInputHits ??
          this.buildShouldRunChangedInputHits,
      buildShouldRunChangedGraphHits:
          buildShouldRunChangedGraphHits ??
          this.buildShouldRunChangedGraphHits,
      assetGraphPersistMilliseconds:
          assetGraphPersistMilliseconds ?? this.assetGraphPersistMilliseconds,
      cacheFlushMilliseconds:
          cacheFlushMilliseconds ?? this.cacheFlushMilliseconds,
      resourceDisposeMilliseconds:
          resourceDisposeMilliseconds ?? this.resourceDisposeMilliseconds,
      mergedOutputsMilliseconds:
          mergedOutputsMilliseconds ?? this.mergedOutputsMilliseconds,
      resolverResetMilliseconds:
          resolverResetMilliseconds ?? this.resolverResetMilliseconds,
      buildLogFinishMilliseconds:
          buildLogFinishMilliseconds ?? this.buildLogFinishMilliseconds,
    );
  }
}

/// Narrow fork of upstream `Build` for custom watch runtime experiments.
///
/// The only behavior change is optional deferral of asset graph persistence so
/// long-lived watch sessions do not serialize the full graph after every build.
class FastBuild {
  final BuildPlan buildPlan;

  // Collaborators.
  final ResourceManager resourceManager;
  final ReaderWriter readerWriter;
  final LibraryCycleGraphLoader previousLibraryCycleGraphLoader =
      LibraryCycleGraphLoader();
  final AssetDepsLoader? previousDepsLoader;
  final Resolvers resolvers;

  /// If [resolvers] is a `ResolversImpl`, the same instance.
  ///
  /// Otherwise, `null`. A different `Resolvers` implementation can be passed
  /// for testing, including via `build_test`.
  final ResolversImpl? resolversImpl;

  // Logging.
  final BuildPerformanceTracker performanceTracker;

  // State.
  final AssetGraph assetGraph;
  final bool persistAssetGraphOnEveryBuild;
  final lazyPhases = <String, Future<Iterable<AssetId>>>{};
  final lazyGlobs = <AssetId, Future<void>>{};

  /// Generated outputs that have been processed.
  ///
  /// That means they have been checked to determine whether they
  /// need building; if so, those have been built, and state has been
  /// updated accordingly.
  final Set<AssetId> processedOutputs = {};

  /// Glob nodes that have been processed.
  ///
  /// That means they have been checked to determine whether they
  /// need evaluating, and if so their state has been updated accordingly.
  final Set<AssetId> processedGlobs = {};

  /// Inputs that changed since the last build.
  ///
  /// Filled from the `updates` passed in to the build.
  final Set<AssetId> changedInputs = {};

  /// Assets that were deleted since the last build.
  ///
  /// This is used to distinguish between `missingSource` nodes that were
  /// already missing and `missingSource` nodes that are newly missing.
  final Set<AssetId> deletedAssets = {};

  /// Assets that might be new primary inputs since the previous build.
  ///
  /// This means: new inputs, new generated outputs, or generated outputs
  /// from generators that failed in the previous build and succeed in this
  /// build.
  final Set<AssetId> newPrimaryInputs = {};

  /// Outputs that changed since the last build.
  ///
  /// Filled during the build as each output is produced and its digest is
  /// checked against the digest from the previous build.
  final Set<AssetId> changedOutputs = {};

  /// Outputs for which errors have been shown.
  final Set<AssetId> errorsShownOutputs = {};

  /// Whether a graph from [previousLibraryCycleGraphLoader] has any changed
  /// transitive source.
  final Map<LibraryCycleGraph, bool> changedGraphs = Map.identity();

  /// The build output.
  BuildOutputReader? _buildOutputReader;
  FastBuildInternalMetrics _lastRunMetrics = FastBuildInternalMetrics.zero;
  int _matchingPrimaryInputsMilliseconds = 0;
  int _buildShouldRunMilliseconds = 0;
  int _buildShouldRunInputCheckMilliseconds = 0;
  int _buildShouldRunGraphCheckMilliseconds = 0;
  int _buildShouldRunInputCheckCount = 0;
  int _buildShouldRunGraphCheckCount = 0;
  int _buildShouldRunChangedInputHits = 0;
  int _buildShouldRunChangedGraphHits = 0;

  FastBuild({
    required this.buildPlan,
    required this.readerWriter,
    required this.resourceManager,
    required this.assetGraph,
    this.persistAssetGraphOnEveryBuild = true,
  }) : performanceTracker =
           buildPlan.buildOptions.trackPerformance
               ? BuildPerformanceTracker()
               : BuildPerformanceTracker.noOp(),
       previousDepsLoader =
           assetGraph.previousPhasedAssetDeps == null
               ? null
               : AssetDepsLoader.fromDeps(assetGraph.previousPhasedAssetDeps!),
       resolvers = buildPlan.testingOverrides.resolvers ?? _defaultResolvers,
       resolversImpl = switch (buildPlan.testingOverrides.resolvers ??
           _defaultResolvers) {
         ResolversImpl r => r,
         _ => null,
       };

  BuildOptions get buildOptions => buildPlan.buildOptions;
  TestingOverrides get testingOverrides => buildPlan.testingOverrides;
  BuildPackages get buildPackages => buildPlan.buildPackages;
  BuildConfigs get buildConfigs => buildPlan.buildConfigs;
  BuildPhases get buildPhases => buildPlan.buildPhases;

  BuildOutputReader get buildOutputReader =>
      _buildOutputReader ??= BuildOutputReader(
        buildPlan: buildPlan,
        readerWriter: readerWriter,
        assetGraph: assetGraph,
        processedOutputs: processedOutputs,
      );

  FastBuildInternalMetrics get lastRunMetrics => _lastRunMetrics;

  Future<BuildResult> run(Map<AssetId, ChangeType> updates) async {
    _lastRunMetrics = FastBuildInternalMetrics.zero;
    _matchingPrimaryInputsMilliseconds = 0;
    _buildShouldRunMilliseconds = 0;
    _buildShouldRunInputCheckMilliseconds = 0;
    _buildShouldRunGraphCheckMilliseconds = 0;
    _buildShouldRunInputCheckCount = 0;
    _buildShouldRunGraphCheckCount = 0;
    _buildShouldRunChangedInputHits = 0;
    _buildShouldRunChangedGraphHits = 0;
    buildLog.configuration = buildLog.configuration.rebuild(
      (b) => b..singleOutputPackage = buildPackages.singleOutputPackage,
    );
    var result = await _safeBuild(updates);
    if (result.status == BuildStatus.success) {
      final failures = <AssetNode>[];
      for (final output in processedOutputs) {
        final node = assetGraph.get(output)!;
        if (node.type != NodeType.generated) continue;
        if (node.generatedNodeState!.result != false) continue;
        failures.add(node);
      }
      if (failures.isNotEmpty) {
        for (final failure in failures) {
          if (errorsShownOutputs.contains(failure.id)) continue;
          final phase =
              buildPhases.inBuildPhases[failure
                  .generatedNodeConfiguration!
                  .phaseNumber];
          final logger = buildLog.loggerFor(
            phase: phase,
            primaryInput: failure.generatedNodeConfiguration!.primaryInput,
            lazy: phase.isOptional,
          );
          for (final error in failure.generatedNodeState!.errors) {
            logger.severe(error);
          }
        }
        result = result.copyWith(status: BuildStatus.failure);
      }
    }
    final cacheFlushStopwatch = Stopwatch()..start();
    readerWriter.cache.flush();
    cacheFlushStopwatch.stop();
    final resourceDisposeStopwatch = Stopwatch()..start();
    await resourceManager.disposeAll();
    resourceDisposeStopwatch.stop();

    // If requested, create output directories. If that fails, fail the build.
    var mergedOutputsMilliseconds = 0;
    if (buildPlan.buildOptions.buildDirs.any(
          (target) => target.outputLocation?.path.isNotEmpty ?? false,
        ) &&
        result.status == BuildStatus.success) {
      final mergedOutputsStopwatch = Stopwatch()..start();
      if (!await createMergedOutputDirectories(
        buildPackages: buildPackages,
        outputSymlinksOnly: buildOptions.outputSymlinksOnly,
        buildDirs: buildOptions.buildDirs,
        buildOutputReader: buildOutputReader,
        readerWriter: readerWriter,
      )) {
        result = result.copyWith(
          status: BuildStatus.failure,
          failureType: FailureType.cantCreate,
        );
      }
      mergedOutputsStopwatch.stop();
      mergedOutputsMilliseconds = mergedOutputsStopwatch.elapsedMilliseconds;
    }

    final resolverResetStopwatch = Stopwatch()..start();
    resolvers.reset();
    resolverResetStopwatch.stop();
    final buildLogFinishStopwatch = Stopwatch()..start();
    result = result.copyWith(
      errors: buildLog.finishBuild(
        result: result.status == BuildStatus.success,
        outputs: result.outputs.length,
      ),
    );
    buildLogFinishStopwatch.stop();
    _lastRunMetrics = _lastRunMetrics.copyWith(
      cacheFlushMilliseconds: cacheFlushStopwatch.elapsedMilliseconds,
      resourceDisposeMilliseconds: resourceDisposeStopwatch.elapsedMilliseconds,
      mergedOutputsMilliseconds: mergedOutputsMilliseconds,
      resolverResetMilliseconds: resolverResetStopwatch.elapsedMilliseconds,
      buildLogFinishMilliseconds: buildLogFinishStopwatch.elapsedMilliseconds,
    );
    return result;
  }

  Future<void> _updateAssetGraph(Map<AssetId, ChangeType> updates) async {
    changedInputs.clear();
    deletedAssets.clear();
    for (final update in updates.entries) {
      if (update.value == ChangeType.REMOVE) {
        deletedAssets.add(update.key);
      } else {
        changedInputs.add(update.key);
        if (update.value == ChangeType.ADD) {
          newPrimaryInputs.add(update.key);
        }
      }
    }
    readerWriter.cache.invalidate(changedInputs);
    final deleted = await assetGraph.updateAndInvalidate(
      buildPhases,
      updates,
      _delete,
      readerWriter,
    );
    deletedAssets.addAll(deleted);
  }

  /// Runs a build inside a zone with an error handler and stack chain
  /// capturing.
  Future<BuildResult> _safeBuild(Map<AssetId, ChangeType> updates) {
    final done = Completer<BuildResult>();
    runZonedGuarded(
      () async {
        var assetGraphUpdateMilliseconds = 0;
        var runPhasesMilliseconds = 0;
        var phasedAssetDepsUpdateMilliseconds = 0;
        var assetGraphPersistMilliseconds = 0;
        if (!assetGraph.cleanBuild) {
          final assetGraphUpdateStopwatch = Stopwatch()..start();
          await _updateAssetGraph(updates);
          assetGraphUpdateStopwatch.stop();
          assetGraphUpdateMilliseconds =
              assetGraphUpdateStopwatch.elapsedMilliseconds;
        }
        await resolversImpl?.takeLockAndStartBuild(assetGraph);
        final runPhasesStopwatch = Stopwatch()..start();
        final result = await _runPhases();
        runPhasesStopwatch.stop();
        runPhasesMilliseconds = runPhasesStopwatch.elapsedMilliseconds;

        assetGraph.previousBuildTriggersDigest =
            buildConfigs.buildTriggers.digest;
        // Combine previous phased asset deps, if any, with the newly loaded
        // deps. Because of skipped builds, the newly loaded deps might just
        // say "not generated yet", in which case the old value is retained.
        final phasedAssetDepsUpdateStopwatch = Stopwatch()..start();
        final currentPhasedAssetDeps =
            resolversImpl?.phasedAssetDeps() ?? PhasedAssetDeps();
        final updatedPhasedAssetDeps =
            assetGraph.previousPhasedAssetDeps == null
                ? currentPhasedAssetDeps
                : assetGraph.previousPhasedAssetDeps!.update(
                  currentPhasedAssetDeps,
                );
        assetGraph.previousPhasedAssetDeps = updatedPhasedAssetDeps;
        phasedAssetDepsUpdateStopwatch.stop();
        phasedAssetDepsUpdateMilliseconds =
            phasedAssetDepsUpdateStopwatch.elapsedMilliseconds;
        if (persistAssetGraphOnEveryBuild) {
          final assetGraphPersistStopwatch = Stopwatch()..start();
          await readerWriter.writeAsBytes(
            AssetId(buildPackages.outputRoot, assetGraphPath),
            assetGraph.serialize(),
          );
          assetGraphPersistStopwatch.stop();
          assetGraphPersistMilliseconds =
              assetGraphPersistStopwatch.elapsedMilliseconds;
        }
        // Phases options don't change during a build series, so for all
        // subsequent builds "previous" and current build options digests
        // match.
        assetGraph.previousInBuildPhasesOptionsDigests =
            assetGraph.inBuildPhasesOptionsDigests;
        assetGraph.previousPostBuildActionsOptionsDigests =
            assetGraph.postBuildActionsOptionsDigests;

        // Log performance information if requested
        if (buildOptions.logPerformanceDir != null) {
          assert(result.performance != null);
          final now = DateTime.now();
          final logPath = p.join(
            buildOptions.logPerformanceDir!,
            '${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)}'
            '_${_twoDigits(now.hour)}-${_twoDigits(now.minute)}-'
            '${_twoDigits(now.second)}',
          );
          buildLog.info('Writing performance log to $logPath');
          final performanceLogId = AssetId(buildPackages.outputRoot, logPath);
          final serialized = jsonEncode(result.performance);
          await readerWriter.writeAsString(performanceLogId, serialized);
        }

        if (!done.isCompleted) done.complete(result);
        _lastRunMetrics = _lastRunMetrics.copyWith(
          assetGraphUpdateMilliseconds: assetGraphUpdateMilliseconds,
          runPhasesMilliseconds: runPhasesMilliseconds,
          phasedAssetDepsUpdateMilliseconds: phasedAssetDepsUpdateMilliseconds,
          matchingPrimaryInputsMilliseconds: _matchingPrimaryInputsMilliseconds,
          buildShouldRunMilliseconds: _buildShouldRunMilliseconds,
          buildShouldRunInputCheckMilliseconds:
              _buildShouldRunInputCheckMilliseconds,
          buildShouldRunGraphCheckMilliseconds:
              _buildShouldRunGraphCheckMilliseconds,
          buildShouldRunInputCheckCount: _buildShouldRunInputCheckCount,
          buildShouldRunGraphCheckCount: _buildShouldRunGraphCheckCount,
          buildShouldRunChangedInputHits: _buildShouldRunChangedInputHits,
          buildShouldRunChangedGraphHits: _buildShouldRunChangedGraphHits,
          assetGraphPersistMilliseconds: assetGraphPersistMilliseconds,
        );
      },
      (e, st) {
        if (!done.isCompleted) {
          buildLog.error(
            buildLog.renderThrowable('Unhandled build failure!', e, st),
          );
          done.complete(
            BuildResult(
              status: BuildStatus.failure,
              outputs: BuiltList(),
              buildOutputReader: buildOutputReader,
            ),
          );
        }
      },
    );

    return done.future;
  }

  /// Runs the actions in [buildPhases] and returns a future which completes
  /// to the [BuildResult] once all [BuildPhase]s are done.
  Future<BuildResult> _runPhases() {
    return performanceTracker.track(() async {
      final outputs = <AssetId>[];
      // Find inputs for non-optional phases, count them for logging.
      final primaryInputsByPhase = <InBuildPhase, List<AssetId>>{};
      final primaryInputCountsByPhase = <InBuildPhase, int>{};
      for (
        var phaseNum = 0;
        phaseNum < buildPhases.inBuildPhases.length;
        phaseNum++
      ) {
        final phase = buildPhases.inBuildPhases[phaseNum];

        if (phase.isOptional) continue;
        final matchingPrimaryInputsStopwatch = Stopwatch()..start();
        final primaryInputs = await _matchingPrimaryInputs(
          phase.package,
          phaseNum,
        );
        matchingPrimaryInputsStopwatch.stop();
        _matchingPrimaryInputsMilliseconds +=
            matchingPrimaryInputsStopwatch.elapsedMilliseconds;
        // If `primaryInputs` is empty, the phase will only run lazily,
        // and might not run at all; so don't log it to start with.
        if (primaryInputs.isNotEmpty) {
          primaryInputsByPhase[phase] = primaryInputs;
          primaryInputCountsByPhase[phase] = primaryInputs.length;
        }
      }

      buildLog.startPhases(
        primaryInputCountsByPhase,
        buildPackages: buildPackages,
      );

      // Main build phases.
      for (
        var phaseNum = 0;
        phaseNum < buildPhases.inBuildPhases.length;
        phaseNum++
      ) {
        final phase = buildPhases.inBuildPhases[phaseNum];
        final primaryInputs = primaryInputsByPhase[phase];
        if (primaryInputs == null || primaryInputs.isEmpty) continue;

        outputs.addAll(
          await performanceTracker.trackBuildPhase(phase, () async {
            final outputs = <AssetId>[];
            for (var i = 0; i != primaryInputs.length; ++i) {
              final primaryInput = primaryInputs[i];
              outputs.addAll(
                await _buildForPrimaryInput(
                  phaseNumber: phaseNum,
                  phase: phase,
                  primaryInput: primaryInput,
                  lazy: false,
                ),
              );
            }
            return outputs;
          }),
        );
      }

      // Post build phase.
      if (buildPhases.postBuildPhase.builderActions.isNotEmpty) {
        outputs.addAll(
          await performanceTracker.trackBuildPhase(
            buildPhases.postBuildPhase,
            () async {
              return _runPostBuildPhase(
                buildPhases.inBuildPhases.length,
                buildPhases.postBuildPhase,
              );
            },
          ),
        );
      }

      await Future.forEach(
        lazyPhases.values,
        (Future<Iterable<AssetId>> lazyOuts) async =>
            outputs.addAll(await lazyOuts),
      );
      // Assume success, `_assetGraph.failedOutputs` will be checked later.
      return BuildResult(
        status: BuildStatus.success,
        outputs: outputs.build(),
        performance: performanceTracker,
        buildOutputReader: buildOutputReader,
      );
    });
  }

  /// Returns primary inputs for [package] in [phaseNumber].
  Future<List<AssetId>> _matchingPrimaryInputs(
    String package,
    int phaseNumber,
  ) async {
    // Accumulate in a `Set` because inputs are found once per output.
    final ids = <AssetId>{};
    final phase = buildPhases[phaseNumber] as InBuildPhase;
    final packageNode = buildPackages[package]!;

    for (final node in assetGraph
        .outputsForPhase(package, phaseNumber)
        .toList(growable: false)) {
      if (!shouldBuildForDirs(
        node.id,
        buildDirs: buildPlan.buildOptions.buildDirs,
        buildFilters: buildPlan.buildOptions.buildFilters,
        phase: phase,
        buildConfigs: buildConfigs,
      )) {
        continue;
      }

      // Don't build for inputs that aren't visible. This can happen for
      // placeholder nodes like `test/$test$` that are added to each package,
      // since the test dir is not part of the build for non-root packages.
      if (!buildConfigs.isVisibleInBuild(node.id, packageNode)) continue;

      ids.add(node.generatedNodeConfiguration!.primaryInput);
    }
    return ids.toList()..sort();
  }

  /// If [id] is a generated asset, ensures that it has been built.
  ///
  /// If has already been built according to [processedOutputs], returns
  /// immediately.
  ///
  /// If it is currently being built according to [lazyPhases], waits for it to
  /// be built.
  Future<void> _buildOutput(AssetId id) async {
    final node = assetGraph.get(id)!;
    if (node.type == NodeType.generated && !processedOutputs.contains(id)) {
      final nodeConfiguration = node.generatedNodeConfiguration!;
      final phaseNumber = nodeConfiguration.phaseNumber;
      final primaryInput = node.generatedNodeConfiguration!.primaryInput;
      await lazyPhases.putIfAbsent('$phaseNumber|$primaryInput', () async {
        final phase = buildPhases.inBuildPhases[nodeConfiguration.phaseNumber];
        return _buildForPrimaryInput(
          primaryInput: primaryInput,
          phaseNumber: phaseNumber,
          phase: phase,
          lazy: true,
        );
      });
    }
  }

  /// Runs the builder for [primaryInput] at [phase].
  ///
  /// If outputs are already valid or are optional and not used, does nothing.
  ///
  /// Returns the files written.
  Future<Iterable<AssetId>> _buildForPrimaryInput({
    required AssetId primaryInput,
    required int phaseNumber,
    required InBuildPhase phase,
    required bool lazy,
  }) async {
    buildLog.startStep(phase: phase, primaryInput: primaryInput, lazy: lazy);
    final builder = phase.builder;
    final tracker = performanceTracker.addBuilderAction(
      primaryInput,
      phase.displayName,
    );
    return tracker.track(() async {
      final singleStepReaderWriter = SingleStepReaderWriter(
        runningBuild: RunningBuild(
          buildPackages: buildPackages,
          buildConfigs: buildConfigs,
          assetGraph: assetGraph,
          nodeBuilder: _buildOutput,
          assetIsProcessedOutput: processedOutputs.contains,
          globNodeBuilder: _buildGlobNode,
        ),
        runningBuildStep: RunningBuildStep(
          phaseNumber: phaseNumber,

          buildPhase: phase,
          primaryPackage: primaryInput.package,
        ),
        readerWriter: readerWriter,
        inputTracker: InputTracker(
          readerWriter.filesystem,
          primaryInput: primaryInput,
          builderLabel: phase.displayName,
        ),
        assetsWritten: {},
      );

      final builderOutputs = expectedOutputs(builder, primaryInput);
      final buildShouldRunStopwatch = Stopwatch()..start();
      final shouldRun = await tracker.trackStage(
        'Setup',
        () => _buildShouldRun(
          phaseNumber,
          primaryInput,
          builderOutputs,
          singleStepReaderWriter,
        ),
      );
      buildShouldRunStopwatch.stop();
      _buildShouldRunMilliseconds += buildShouldRunStopwatch.elapsedMilliseconds;
      if (!shouldRun) {
        buildLog.skipStep(phase: phase, lazy: lazy);
        return <AssetId>[];
      }

      await _cleanUpStaleOutputs(builderOutputs);

      // Clear input tracking accumulated during `_buildShouldRun`.
      singleStepReaderWriter.inputTracker.clear();

      final unusedAssets = <AssetId>{};
      void reportUnusedAssetsForInput(AssetId input, Iterable<AssetId> assets) {
        testingOverrides.reportUnusedAssetsForInput?.call(input, assets);
        unusedAssets.addAll(assets);
      }

      // Pass `readerWriter` so that if `_allowedByTriggers` reads files to
      // evaluate triggers then they are tracked as inputs.
      final allowedByTriggers = await _allowedByTriggers(
        readerWriter: singleStepReaderWriter,
        phase: phase,
        primaryInput: primaryInput,
      );
      final logger = buildLog.loggerFor(
        phase: phase,
        primaryInput: primaryInput,
        lazy: lazy,
      );
      if (allowedByTriggers) {
        await TimedActivity.build.runAsync(
          () => tracker.trackStage('Build', () {
            return runBuilder(
              builder,
              [primaryInput],
              singleStepReaderWriter,
              PerformanceTrackingResolvers(resolvers, tracker),
              logger: logger,
              resourceManager: resourceManager,
              stageTracker: tracker,
              reportUnusedAssetsForInput: reportUnusedAssetsForInput,
              packageConfig: buildPackages.asPackageConfig,
            ).catchError((void _) {
              // Errors tracked through the logger.
            });
          }),
        );
      }

      // Update the state for all the `builderOutputs` nodes based on what was
      // read and written.
      await TimedActivity.track.runAsync(
        () => tracker.trackStage(
          'Finalize',
          () => _setOutputsState(
            primaryInput,
            builderOutputs,
            singleStepReaderWriter,
            logger.errors,
            unusedAssets: unusedAssets,
          ),
        ),
      );

      if (allowedByTriggers) {
        buildLog.finishStep(
          phase: phase,
          anyOutputs: singleStepReaderWriter.assetsWritten.isNotEmpty,
          anyChangedOutputs: singleStepReaderWriter.assetsWritten.any(
            changedOutputs.contains,
          ),
          lazy: lazy,
        );
      } else {
        buildLog.stepNotTriggered(phase: phase, lazy: lazy);
      }

      return singleStepReaderWriter.assetsWritten;
    });
  }

  /// Whether build triggers allow [phase] to run on [primaryInput].
  ///
  /// This means either the builder does not have `run_only_if_triggered: true`
  /// or it does run only if triggered and is triggered.
  Future<bool> _allowedByTriggers({
    required SingleStepReaderWriter readerWriter,
    required InBuildPhase phase,
    required AssetId primaryInput,
  }) async {
    final runsIfTriggered = phase.options.config['run_only_if_triggered'];
    if (runsIfTriggered != true) {
      return true;
    }
    final buildTriggers = buildConfigs.buildTriggers[phase.key];
    if (buildTriggers == null) {
      return false;
    }
    final primaryInputSource = await readerWriter.readAsString(primaryInput);
    final compilationUnit = _parseCompilationUnit(primaryInputSource);
    List<CompilationUnit>? compilationUnits;
    for (final trigger in buildTriggers) {
      if (trigger.checksParts) {
        compilationUnits ??= await _readAndParseCompilationUnits(
          readerWriter,
          primaryInput,
          compilationUnit,
        );
        if (trigger.triggersOn(compilationUnits)) return true;
      } else {
        if (trigger.triggersOn([compilationUnit])) return true;
      }
    }
    return false;
  }

  /// TODO(davidmorgan): cache parse results, share with deps parsing and
  /// builder parsing.
  static CompilationUnit _parseCompilationUnit(String content) {
    return parseString(content: content, throwIfDiagnostics: false).unit;
  }

  static Future<List<CompilationUnit>> _readAndParseCompilationUnits(
    SingleStepReaderWriter stepReaderWriter,
    AssetId id,
    CompilationUnit compilationUnit,
  ) async {
    final result = [compilationUnit];
    for (final directive in compilationUnit.directives) {
      if (directive is! PartDirective) continue;
      final partId = AssetId.resolve(
        Uri.parse(directive.uri.stringValue!),
        from: id,
      );
      if (!await stepReaderWriter.canRead(partId)) continue;
      result.add(
        _parseCompilationUnit(await stepReaderWriter.readAsString(partId)),
      );
    }
    return result;
  }

  Future<Iterable<AssetId>> _runPostBuildPhase(
    int phaseNum,
    PostBuildPhase phase,
  ) async {
    var actionNum = 0;
    final outputs = <AssetId>[];
    for (final builderAction in phase.builderActions) {
      outputs.addAll(
        await _runPostBuildAction(phaseNum, actionNum++, builderAction),
      );
    }
    return outputs;
  }

  Future<Iterable<AssetId>> _runPostBuildAction(
    int phaseNum,
    int actionNum,
    PostBuildAction action,
  ) async {
    final outputs = <AssetId>[];
    for (final buildStepId in assetGraph.postProcessBuildStepIds(
      package: action.package,
    )) {
      if (buildStepId.actionNumber != actionNum) continue;
      final inputNode = assetGraph.get(buildStepId.input)!;
      if (inputNode.type == NodeType.source ||
          inputNode.type == NodeType.generated && inputNode.wasOutput) {
        outputs.addAll(
          await _runPostProcessBuildStep(
            phaseNum,
            action.builder,
            buildStepId,
            hideOutput: action.hideOutput,
          ),
        );
      }
    }
    return outputs;
  }

  Future<Iterable<AssetId>> _runPostProcessBuildStep(
    int phaseNumber,
    PostProcessBuilder builder,
    PostProcessBuildStepId postProcessBuildStepId, {
    required bool hideOutput,
  }) async {
    final input = postProcessBuildStepId.input;
    final inputNode = assetGraph.get(input)!;
    final stepReaderWriter = SingleStepReaderWriter(
      runningBuild: RunningBuild(
        buildPackages: buildPackages,
        buildConfigs: buildConfigs,
        assetGraph: assetGraph,
        nodeBuilder: _buildOutput,
        assetIsProcessedOutput: processedOutputs.contains,
        globNodeBuilder: _buildGlobNode,
      ),
      runningBuildStep: RunningBuildStep(
        phaseNumber: phaseNumber,
        buildPhase: buildPhases.postBuildPhase,
        primaryPackage: input.package,
      ),
      readerWriter: readerWriter,
      inputTracker: InputTracker(readerWriter.filesystem, primaryInput: input),
      assetsWritten: {},
    );

    final existingOutputs = assetGraph.postProcessBuildStepOutputs(
      postProcessBuildStepId,
    );
    if (!await _postProcessBuildStepShouldRun(
      postProcessBuildStepId,
      stepReaderWriter,
    )) {
      processedOutputs.addAll(existingOutputs);
      return <AssetId>[];
    }
    // Clear input tracking accumulated during `_buildShouldRun`.
    stepReaderWriter.inputTracker.clear();

    // Clean out the impacts of the previous run.
    await _cleanUpStaleOutputs(existingOutputs);
    for (final output in existingOutputs) {
      assetGraph.removePostProcessOutput(output);
    }
    assetGraph.updateNode(inputNode.id, (nodeBuilder) {
      nodeBuilder.deletedBy.remove(postProcessBuildStepId);
    });

    final logger = buildLog.loggerForOther(
      buildLog.renderId(input),
      contextId: input,
    );
    final outputs = <AssetId>{};
    await runPostProcessBuilder(
      builder,
      input,
      stepReaderWriter,
      logger,
      addAsset: (assetId) {
        if (assetGraph.contains(assetId)) {
          throw InvalidOutputException(assetId, 'Asset already exists');
        }
        final node = AssetNode.generated(
          assetId,
          primaryInput: input,
          isHidden: hideOutput,
          phaseNumber: phaseNumber,
        );
        assetGraph.add(node);
        outputs.add(assetId);
      },
      deleteAsset: (assetId) {
        if (!assetGraph.contains(assetId)) {
          throw AssetNotFoundException(assetId);
        }
        if (assetId != input) {
          throw InvalidOutputException(
            assetId,
            'Can only delete primary input',
          );
        }
        assetGraph.updateNode(assetId, (nodeBuilder) {
          nodeBuilder.deletedBy.add(postProcessBuildStepId);
        });
      },
    ).catchError((void _) {
      // Errors tracked through the logger
    });

    assetGraph.updatePostProcessBuildStep(
      postProcessBuildStepId,
      outputs: outputs,
    );

    final assetsWritten = stepReaderWriter.assetsWritten.toSet();

    // Reset the state for all the output nodes based on what was read and
    // written.
    assetGraph.updateNode(inputNode.id, (nodeBuilder) {
      nodeBuilder.primaryOutputs.addAll(assetsWritten);
    });

    await _setOutputsState(
      input,
      assetsWritten,
      stepReaderWriter,
      logger.errors,
    );

    return assetsWritten;
  }

  /// Marks [outputs] as not output and not built.
  void _markOutputsSkipped(Iterable<AssetId> outputs) {
    for (final output in outputs) {
      assetGraph.updateNode(output, (nodeBuilder) {
        nodeBuilder.digest = null;
        nodeBuilder.generatedNodeState.result = null;
      });
      processedOutputs.add(output);
    }
  }

  /// Marks [outputs] as not output and failed.
  Future<void> _markOutputsTransitivelyFailed(Iterable<AssetId> outputs) async {
    for (final output in outputs) {
      assetGraph.updateNode(output, (nodeBuilder) {
        nodeBuilder.digest = null;
        nodeBuilder.generatedNodeState.result = false;
        nodeBuilder.generatedNodeState.errors.clear();
      });
      processedOutputs.add(output);
    }
  }

  /// Checks and returns whether any [outputs] need to be updated in
  /// [phaseNumber] for [primaryInput].
  ///
  /// As part of checking, builds any inputs that need building.
  Future<bool> _buildShouldRun(
    int phaseNumber,
    AssetId primaryInput,
    Iterable<AssetId> outputs,
    SingleStepReaderWriter readerWriter,
  ) async {
    return await TimedActivity.track.runAsync(() async {
      // Update state for primary input if needed.
      var primaryInputNode = assetGraph.get(primaryInput)!;
      if (primaryInputNode.type == NodeType.generated) {
        if (!processedOutputs.contains(primaryInput)) {
          await _buildOutput(primaryInput);
          primaryInputNode = assetGraph.get(primaryInput)!;
        }
      }

      // If the primary input has been deleted, the build is skipped.
      if (deletedAssets.contains(primaryInput)) {
        if (primaryInputNode.type == NodeType.missingSource) {
          await _cleanUpStaleOutputs(outputs);
          _markOutputsSkipped(outputs);
          return false;
        }
      }

      // Propagate results for generated node inputs.
      if (primaryInputNode.type == NodeType.generated) {
        // If the primary input is failed, this build is also failed.
        if (primaryInputNode.generatedNodeState!.result == false) {
          await _markOutputsTransitivelyFailed(outputs);
          return false;
        }

        // If the primary input succeeded but was not output, this build is
        // skipped.
        if (!primaryInputNode.wasOutput) {
          await _cleanUpStaleOutputs(outputs);
          _markOutputsSkipped(outputs);
          return false;
        }
      }

      if (assetGraph.cleanBuild) return true;

      if (assetGraph.previousBuildTriggersDigest !=
          buildConfigs.buildTriggers.digest) {
        return true;
      }

      if (assetGraph.previousInBuildPhasesOptionsDigests![phaseNumber] !=
          assetGraph.inBuildPhasesOptionsDigests[phaseNumber]) {
        return true;
      }

      if (newPrimaryInputs.contains(primaryInput)) return true;

      for (final output in outputs) {
        if (deletedAssets.contains(output)) return true;
      }

      // Build results are the same across outputs, so just check the first
      // output.
      final firstOutput = assetGraph.get(outputs.first)!;
      final firstOutputState = firstOutput.generatedNodeState!;

      if (firstOutputState.result == null) return true;

      // Check for changes to any inputs.
      final inputs = firstOutputState.inputs;
      if (_hasDirectSourceLikeInputChange(inputs)) {
        _buildShouldRunChangedInputHits++;
        return true;
      }

      for (final input in inputs) {
        final inputNode = assetGraph.get(input)!;
        if (inputNode.type == NodeType.source ||
            inputNode.type == NodeType.missingSource) {
          continue;
        }
        _buildShouldRunInputCheckCount++;
        final inputCheckStopwatch = Stopwatch()..start();
        final changed = await _hasNonSourceInputChanged(
          inputNode: inputNode,
          phaseNumber: phaseNumber,
        );
        inputCheckStopwatch.stop();
        _buildShouldRunInputCheckMilliseconds +=
            inputCheckStopwatch.elapsedMilliseconds;

        if (changed) {
          _buildShouldRunChangedInputHits++;
          return true;
        }
      }

      for (final graphId in firstOutputState.resolverEntrypoints) {
        _buildShouldRunGraphCheckCount++;
        final graphCheckStopwatch = Stopwatch()..start();
        final changed = await _hasInputGraphChanged(
          phaseNumber: phaseNumber,
          entrypointId: graphId,
        );
        graphCheckStopwatch.stop();
        _buildShouldRunGraphCheckMilliseconds +=
            graphCheckStopwatch.elapsedMilliseconds;
        if (changed) {
          _buildShouldRunChangedGraphHits++;
          return true;
        }
      }

      // No input changes: build is not needed, and outputs state is up to date.
      for (final output in outputs) {
        processedOutputs.add(output);
      }

      return false;
    });
  }

  /// Whether any source in the _previous build_ transitive import graph
  /// of [entrypointId] has a change visible at [phaseNumber].
  ///
  /// There is a tradeoff between returning early when a first change is
  /// encountered and continuing to process the graph to produce results that
  /// might be useful later. This implementation is eager, it computes whether
  /// every subgraph reachable from [entrypointId] has changed.
  Future<bool> _hasInputGraphChanged({
    required AssetId entrypointId,
    required int phaseNumber,
  }) async {
    // If the result has already been calculated, return it.
    final entrypointGraph = (await previousLibraryCycleGraphLoader
        .libraryCycleGraphOf(
          previousDepsLoader!,
          entrypointId,
        )).valueAt(phase: phaseNumber);
    final maybeResult = changedGraphs[entrypointGraph];
    if (maybeResult != null) {
      return maybeResult;
    }

    final graphsToCheckStack = [entrypointGraph];

    while (graphsToCheckStack.isNotEmpty) {
      final nextGraph = graphsToCheckStack.last;

      // If there are multiple paths to a node, it might have been calculated
      // for another path.
      if (changedGraphs.containsKey(nextGraph)) {
        graphsToCheckStack.removeLast();
        continue;
      }

      // Determine whether there are child graphs not yet evaluated.
      //
      // If so, add them to the stack and "continue" to evaluate those before
      // returning to this graph.
      final childGraphsWithWorkToDo = <LibraryCycleGraph>[];
      for (final childGraph in nextGraph.children) {
        final maybeChildResult = changedGraphs[childGraph];
        if (maybeChildResult == null) {
          childGraphsWithWorkToDo.add(childGraph);
        }
      }
      if (childGraphsWithWorkToDo.isNotEmpty) {
        graphsToCheckStack.addAll(childGraphsWithWorkToDo);
        continue;
      }

      // Determine whether the graph root library cycle has any changed IDs. If
      // so, the graph has changed; if not, check whether any child graph
      // changed.
      var rootLibraryCycleHasChanged = false;
      for (final id in nextGraph.root.ids) {
        if (await _hasInputChanged(phaseNumber: phaseNumber, input: id)) {
          rootLibraryCycleHasChanged = true;
          break;
        }
      }
      if (rootLibraryCycleHasChanged) {
        changedGraphs[nextGraph] = true;
      } else {
        var anyChildHasChanged = false;
        for (final childGraph in nextGraph.children) {
          final childResult = changedGraphs[childGraph];
          if (childResult == null) {
            throw StateError('Child graphs should have been checked.');
          } else if (childResult) {
            anyChildHasChanged = true;
            break;
          }
        }
        changedGraphs[nextGraph] = anyChildHasChanged;
      }
      graphsToCheckStack.removeLast();
    }

    return changedGraphs[entrypointGraph]!;
  }

  /// Whether [input] has a change visible at [phaseNumber].
  Future<bool> _hasInputChanged({
    required AssetId input,
    required int phaseNumber,
  }) async {
    final inputNode = assetGraph.get(input)!;
    return _hasInputChangedForNode(
      inputNode: inputNode,
      phaseNumber: phaseNumber,
    );
  }

  bool _hasDirectSourceLikeInputChange(BuiltSet<AssetId> inputs) {
    for (final changedInput in changedInputs) {
      if (!inputs.contains(changedInput)) {
        continue;
      }
      final changedNode = assetGraph.get(changedInput);
      if (changedNode?.type == NodeType.source) {
        return true;
      }
    }

    for (final deletedInput in deletedAssets) {
      if (!inputs.contains(deletedInput)) {
        continue;
      }
      final deletedNode = assetGraph.get(deletedInput);
      if (deletedNode?.type == NodeType.source ||
          deletedNode?.type == NodeType.missingSource) {
        return true;
      }
    }

    return false;
  }

  Future<bool> _hasNonSourceInputChanged({
    required AssetNode inputNode,
    required int phaseNumber,
  }) {
    assert(
      inputNode.type != NodeType.source &&
          inputNode.type != NodeType.missingSource,
      'Source-like inputs should be handled by the direct-change prefilter.',
    );
    return _hasInputChangedForNode(
      inputNode: inputNode,
      phaseNumber: phaseNumber,
    );
  }

  Future<bool> _hasInputChangedForNode({
    required AssetNode inputNode,
    required int phaseNumber,
  }) async {
    final input = inputNode.id;
    if (inputNode.type == NodeType.generated) {
      if (inputNode.generatedNodeConfiguration!.phaseNumber >= phaseNumber) {
        // It's not readable in this phase.
        return false;
      }
      // Ensure that the input was built, so [changedOutputs] is updated.
      if (!processedOutputs.contains(input)) {
        await _buildOutput(inputNode.id);
      }
      if (changedOutputs.contains(input)) {
        return true;
      }
    } else if (inputNode.type == NodeType.glob) {
      // Ensure that the glob was evaluated, so [changedOutputs] is updated.
      if (!processedGlobs.contains(input)) {
        await _buildGlobNode(input);
      }
      if (changedOutputs.contains(input)) {
        return true;
      }
    } else if (inputNode.type == NodeType.source) {
      if (changedInputs.contains(input)) {
        return true;
      }
    } else if (inputNode.type == NodeType.missingSource) {
      // It's only a newly-deleted asset if it's also in [deletedAssets].
      if (deletedAssets.contains(input)) {
        return true;
      }
    }
    return false;
  }

  /// Whether the post process build step [buildStepId] should run.
  ///
  /// It should run if its builder options changed or its input changed.
  Future<bool> _postProcessBuildStepShouldRun(
    PostProcessBuildStepId buildStepId,
    SingleStepReaderWriter stepReaderWriter,
  ) async {
    final input = buildStepId.input;
    final node = assetGraph.get(input)!;

    if (assetGraph.cleanBuild) {
      return true;
    }

    if (assetGraph.previousPostBuildActionsOptionsDigests![buildStepId
            .actionNumber] !=
        assetGraph.postBuildActionsOptionsDigests[buildStepId.actionNumber]) {
      return true;
    }

    if (node.type == NodeType.generated) {
      // Check that the input was built, so [changedOutputs] is updated.
      if (!processedOutputs.contains(node.id)) {
        await _buildOutput(node.id);
      }
      if (changedOutputs.contains(input)) {
        return true;
      }
    } else if (node.type == NodeType.source) {
      if (changedInputs.contains(input)) {
        return true;
      }
    } else {
      throw StateError('Expected generated or source node: $node');
    }

    return false;
  }

  /// Deletes any of [outputs] which previously were output.
  ///
  /// This should be called after deciding that an asset really needs to be
  /// regenerated based on its inputs hash changing. All assets in [outputs]
  /// must correspond to a [AssetNode.generated].
  Future<void> _cleanUpStaleOutputs(Iterable<AssetId> outputs) async {
    for (final output in outputs) {
      final node = assetGraph.get(output)!;
      if (node.type == NodeType.generated && node.wasOutput) {
        await _delete(output);
      }
    }
  }

  /// Builds the glob node with [globId].
  ///
  /// This means finding matches of the glob and building them if necessary.
  ///
  /// Generated files are special for two reasons.
  ///
  /// First, they are only visible to the glob if they are generated in an
  /// earlier phase than the phase in which the glob is evaluated. If not, they
  /// are totally invisible: nothing is done for them.
  ///
  /// Second, a generated file might not actually be generated: its builder
  /// might choose at runtime to output nothing. In this case, the non-existent
  /// generated file is still tracked as an input that matched the glob, but is
  /// not useful to something that wants to read the file. On the glob node, it
  /// ends up in `inputs` but not in `results`.
  ///
  ///
  Future<void> _buildGlobNode(AssetId globId) async {
    if (processedGlobs.contains(globId)) {
      return;
    }

    return lazyGlobs.putIfAbsent(globId, () async {
      final globNodeConfiguration =
          assetGraph.get(globId)!.globNodeConfiguration!;
      final glob = Glob(globNodeConfiguration.glob);

      // Generated files that match the glob.
      final generatedFileInputs = <AssetId>[];
      // Other types of file that match the glob.
      final otherInputs = <AssetId>[];

      for (final id in assetGraph.packageFileIds(globId.package, glob: glob)) {
        final node = assetGraph.get(id)!;
        // Generated nodes are only considered at all if they are output in
        // an earlier phase.
        if (node.type != NodeType.generated ||
            node.generatedNodeConfiguration!.phaseNumber <
                globNodeConfiguration.phaseNumber) {
          if (node.type == NodeType.generated) {
            generatedFileInputs.add(node.id);
          } else {
            otherInputs.add(node.id);
          }
        }
      }

      // Request to build the matching generated files.
      for (final id in generatedFileInputs) {
        await _buildOutput(id);
      }

      // The generated file matches that were output are part of the results of
      // the glob.
      final generatedFileResults = <AssetId>[];
      for (final id in generatedFileInputs) {
        final node = assetGraph.get(id)!;
        if (node.wasOutput && node.generatedNodeState!.result == true) {
          generatedFileResults.add(id);
        }
      }

      final results = [...otherInputs, ...generatedFileResults];
      final digest = md5.convert(utf8.encode(results.join(' ')));
      assetGraph.updateNode(globId, (nodeBuilder) {
        if (nodeBuilder.digest != digest) {
          changedOutputs.add(globId);
        }
        processedGlobs.add(globId);
        nodeBuilder
          ..globNodeState.results.replace(results)
          ..globNodeState.inputs.replace(
            generatedFileInputs.followedBy(otherInputs),
          )
          ..digest = digest;
      });

      unawaited(lazyGlobs.remove(globId));
    });
  }

  /// Sets the state for all [outputs] of a build step, by:
  ///
  /// - Setting `digest` based on what was written.
  /// - Setting `result` based on action success.
  /// - Setting `inputs` based on `inputTracker` and `unusedAssets`.
  /// - Setting `errors`.
  /// - Updating `newPrimaryInputs` and `changedOutputs` as needed.
  Future<void> _setOutputsState(
    AssetId input,
    Iterable<AssetId> outputs,
    SingleStepReaderWriter stepReaderWriter,
    Iterable<String> errors, {
    Set<AssetId>? unusedAssets,
  }) async {
    if (outputs.isEmpty) return;
    final inputTracker = stepReaderWriter.inputTracker;
    final usedInputs =
        unusedAssets != null && unusedAssets.isNotEmpty
            ? inputTracker.inputs.difference(unusedAssets)
            : inputTracker.inputs;

    final result = errors.isEmpty;

    for (final output in outputs) {
      final wasOutput = stepReaderWriter.assetsWritten.contains(output);
      final digest = wasOutput ? await readerWriter.digest(output) : null;
      var outputNode = assetGraph.get(output)!;

      // A transition from (missing or failed) to (written and not failed) is
      // a new primary input that triggers generation even if no content
      // changed.
      if ((outputNode.digest == null ||
              outputNode.generatedNodeState!.result == false) &&
          (digest != null && result)) {
        newPrimaryInputs.add(output);
      }
      // Only a change to content matters for non-primary inputs.
      if (outputNode.digest != digest) {
        changedOutputs.add(output);
      }

      outputNode = assetGraph.updateNode(output, (nodeBuilder) {
        nodeBuilder.generatedNodeState
          ..inputs.replace(usedInputs)
          ..resolverEntrypoints.replace(inputTracker.resolverEntrypoints)
          ..result = result
          ..errors.replace(errors);
        nodeBuilder.digest = digest;
      });

      processedOutputs.add(output);
      if (result == false) {
        errorsShownOutputs.add(output);
      }
    }
  }

  Future _delete(AssetId id) => readerWriter.delete(id);
}

String _twoDigits(int n) => '$n'.padLeft(2, '0');
