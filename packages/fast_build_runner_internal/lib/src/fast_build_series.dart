// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:build/build.dart';
import 'package:build_runner/src/build/build_result.dart';
import 'package:build_runner/src/build/asset_graph/graph.dart';
import 'package:build_runner/src/build_plan/build_directory.dart';
import 'package:build_runner/src/build_plan/build_filter.dart';
import 'package:build_runner/src/build_plan/build_plan.dart';
import 'package:build_runner/src/constants.dart';
import 'package:build_runner/src/io/asset_tracker.dart';
import 'package:build_runner/src/io/filesystem_cache.dart';
import 'package:build_runner/src/io/generated_asset_hider.dart';
import 'package:build_runner/src/io/reader_writer.dart';
import 'package:build_runner/src/logging/build_log.dart';
import 'package:built_collection/built_collection.dart';
import 'package:watcher/watcher.dart';

import 'deferred_asset_graph_reader_writer.dart';
import 'fast_build.dart';
import 'fast_build_run_profile.dart';

/// Narrow copy of upstream BuildSeries for the bootstrap spike.
///
/// The upstream implementation rebuilds a derived BuildPlan with copyWith() on
/// every run. That is fine for the stock BuildPlan, but our FastBuildPlan owns
/// a custom bootstrapper and a taken AssetGraph, so a local series wrapper is
/// simpler and less error-prone for the spike.
class FastBuildSeries {
  BuildPlan _buildPlan;
  AssetGraph _assetGraph;
  ReaderWriter _readerWriter;

  final ResourceManager _resourceManager = ResourceManager();
  final StreamController<BuildResult> _buildResultsController =
      StreamController.broadcast();
  final Completer<void> _closingCompleter = Completer<void>();

  BuiltMap<AssetId, ChangeType>? _updatesFromLoad;
  Future<BuildResult>? _currentBuildResult;
  bool _assetGraphNeedsPersistence = false;
  bool firstBuild = true;

  FastBuildSeries._({
    required BuildPlan buildPlan,
    required AssetGraph assetGraph,
    required ReaderWriter readerWriter,
    required BuiltMap<AssetId, ChangeType>? updatesFromLoad,
  }) : _buildPlan = buildPlan,
       _assetGraph = assetGraph,
       _readerWriter = readerWriter,
       _updatesFromLoad = updatesFromLoad;

  factory FastBuildSeries(BuildPlan buildPlan) {
    final assetGraph = buildPlan.takeAssetGraph();
    return FastBuildSeries._(
      buildPlan: buildPlan,
      assetGraph: assetGraph,
      readerWriter: _createReaderWriter(buildPlan, assetGraph),
      updatesFromLoad: buildPlan.updates,
    );
  }

  Stream<BuildResult> get buildResults => _buildResultsController.stream;

  Future<Map<AssetId, ChangeType>> collectSourceUpdates() {
    return AssetTracker(
      _buildPlan.readerWriter,
      _buildPlan.buildPackages,
      _buildPlan.buildConfigs,
    ).collectChanges(_assetGraph);
  }

  Future<FastBuildRunOutcome> run(
    Map<AssetId, ChangeType> updates, {
    required bool recentlyBootstrapped,
    bool skipBuildScriptFreshnessCheck = false,
    BuiltSet<BuildDirectory>? buildDirs,
    BuiltSet<BuildFilter>? buildFilters,
  }) async {
    if (_closingCompleter.isCompleted) {
      throw StateError('FastBuildSeries was closed.');
    }
    if (buildDirs != null || buildFilters != null) {
      throw UnsupportedError(
        'FastBuildSeries does not yet support buildDirs/buildFilters overrides.',
      );
    }

    var freshnessCheckMilliseconds = 0;
    var configReloadMilliseconds = 0;

    if (recentlyBootstrapped) {
      if (updates.isNotEmpty) {
        throw StateError('`recentlyBootstrapped` but updates not empty.');
      }
    } else if (!skipBuildScriptFreshnessCheck) {
      final freshnessStopwatch = Stopwatch()..start();
      final kernelFreshness = await _buildPlan.bootstrapper
          .checkCompileFreshness(digestsAreFresh: false);
      freshnessStopwatch.stop();
      freshnessCheckMilliseconds = freshnessStopwatch.elapsedMilliseconds;
      if (!kernelFreshness.outputIsFresh) {
        final result = BuildResult.buildScriptChanged();
        _buildResultsController.add(result);
        await close();
        return FastBuildRunOutcome(
          result: result,
          profile: FastBuildRunProfile(
            freshnessCheckMilliseconds: freshnessCheckMilliseconds,
            configReloadMilliseconds: 0,
            buildRunMilliseconds: 0,
            trackedActionMilliseconds: 0,
            trackedPhaseMilliseconds: 0,
            trackedBuilderActionCount: 0,
            trackedBuildPhaseCount: 0,
            assetGraphSerializeProbeMilliseconds: 0,
            assetGraphSerializeProbeBytes: 0,
          ),
        );
      }
    }

    if (updates.keys.any(_isBuildConfiguration)) {
      final configReloadStopwatch = Stopwatch()..start();
      await _flushDeferredWrites();
      _buildPlan = await _buildPlan.reload();
      await _buildPlan.deleteFilesAndFolders();
      if (_buildPlan.restartIsNeeded) {
        configReloadStopwatch.stop();
        configReloadMilliseconds = configReloadStopwatch.elapsedMilliseconds;
        final result = BuildResult.buildScriptChanged();
        _buildResultsController.add(result);
        await close();
        return FastBuildRunOutcome(
          result: result,
          profile: FastBuildRunProfile(
            freshnessCheckMilliseconds: freshnessCheckMilliseconds,
            configReloadMilliseconds: configReloadMilliseconds,
            buildRunMilliseconds: 0,
            trackedActionMilliseconds: 0,
            trackedPhaseMilliseconds: 0,
            trackedBuilderActionCount: 0,
            trackedBuildPhaseCount: 0,
            assetGraphSerializeProbeMilliseconds: 0,
            assetGraphSerializeProbeBytes: 0,
          ),
        );
      }
      _assetGraph = _buildPlan.takeAssetGraph();
      _readerWriter = _createReaderWriter(_buildPlan, _assetGraph);
      configReloadStopwatch.stop();
      configReloadMilliseconds = configReloadStopwatch.elapsedMilliseconds;
    }

    if (firstBuild) {
      if (_updatesFromLoad != null) {
        updates = _updatesFromLoad!.toMap()..addAll(updates);
        _updatesFromLoad = null;
      }
    } else if (_updatesFromLoad != null) {
      throw StateError('Only first build can have updates from load.');
    }

    if (!firstBuild) buildLog.nextBuild();
    final build = FastBuild(
      buildPlan: _buildPlan,
      assetGraph: _assetGraph,
      readerWriter: _readerWriter,
      resourceManager: _resourceManager,
      persistAssetGraphOnEveryBuild: false,
    );
    if (firstBuild) {
      firstBuild = false;
    }

    final buildRunStopwatch = Stopwatch()..start();
    _currentBuildResult = build.run(updates);
    final result = await _currentBuildResult!;
    buildRunStopwatch.stop();
    if (result.status == BuildStatus.success) {
      _assetGraphNeedsPersistence = true;
    }
    final assetGraphSerializeProbeStopwatch = Stopwatch()..start();
    final assetGraphBytes = _assetGraph.serialize();
    assetGraphSerializeProbeStopwatch.stop();
    _buildResultsController.add(result);
    return FastBuildRunOutcome(
      result: result,
      profile: FastBuildRunProfile.fromBuildResult(
        buildResult: result,
        freshnessCheckMilliseconds: freshnessCheckMilliseconds,
        configReloadMilliseconds: configReloadMilliseconds,
        buildRunMilliseconds: buildRunStopwatch.elapsedMilliseconds,
        assetGraphSerializeProbeMilliseconds:
            assetGraphSerializeProbeStopwatch.elapsedMilliseconds,
        assetGraphSerializeProbeBytes: assetGraphBytes.length,
      ),
    );
  }

  Future<void> close() async {
    if (_closingCompleter.isCompleted) {
      return;
    }
    _closingCompleter.complete();
    await _currentBuildResult;
    await _flushDeferredWrites();
    await _resourceManager.beforeExit();
    await _buildResultsController.close();
  }

  Future<void> _flushDeferredWrites() async {
    if (_readerWriter is DeferredAssetGraphReaderWriter) {
      final deferredReaderWriter =
          _readerWriter as DeferredAssetGraphReaderWriter;
      if (_assetGraphNeedsPersistence &&
          !deferredReaderWriter.hasBufferedAssetGraphWrite) {
        deferredReaderWriter.bufferAssetGraphBytes(_assetGraph.serialize());
      }
      await deferredReaderWriter.flushDeferredWrites();
      _assetGraphNeedsPersistence = false;
    }
  }

  bool _isBuildConfiguration(AssetId id) =>
      id.path == 'build.yaml' || id.path.startsWith(entrypointDirectoryPath);

  static ReaderWriter _createReaderWriter(
    BuildPlan buildPlan,
    AssetGraph assetGraph,
  ) {
    final baseReaderWriter = buildPlan.readerWriter.copyWith(
      generatedAssetHider: buildPlan.testingOverrides.flattenOutput
          ? const NoopGeneratedAssetHider()
          : assetGraph,
      cache: buildPlan.buildOptions.enableLowResourcesMode
          ? const PassthroughFilesystemCache()
          : InMemoryFilesystemCache(),
    );
    return DeferredAssetGraphReaderWriter(
      delegate: baseReaderWriter,
      assetGraphId: AssetId(buildPlan.buildPackages.outputRoot, assetGraphPath),
    );
  }
}
