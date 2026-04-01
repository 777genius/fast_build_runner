// ignore_for_file: implementation_imports, experimental_member_use

import 'dart:math' as math;

import 'package:build_runner/src/build/build_result.dart';

class FastBuildRunProfile {
  final int freshnessCheckMilliseconds;
  final int configReloadMilliseconds;
  final int buildRunMilliseconds;
  final int assetGraphUpdateMilliseconds;
  final int runPhasesMilliseconds;
  final int phasedAssetDepsUpdateMilliseconds;
  final int matchingPrimaryInputsMilliseconds;
  final int buildShouldRunMilliseconds;
  final int trackedActionMilliseconds;
  final int trackedActionWallMilliseconds;
  final int trackedPhaseMilliseconds;
  final int trackedBuilderActionCount;
  final int trackedBuildPhaseCount;
  final int assetGraphPersistMilliseconds;
  final int cacheFlushMilliseconds;
  final int resourceDisposeMilliseconds;
  final int mergedOutputsMilliseconds;
  final int resolverResetMilliseconds;
  final int buildLogFinishMilliseconds;
  final int assetGraphSerializeProbeMilliseconds;
  final int assetGraphSerializeProbeBytes;

  const FastBuildRunProfile({
    required this.freshnessCheckMilliseconds,
    required this.configReloadMilliseconds,
    required this.buildRunMilliseconds,
    required this.assetGraphUpdateMilliseconds,
    required this.runPhasesMilliseconds,
    required this.phasedAssetDepsUpdateMilliseconds,
    required this.matchingPrimaryInputsMilliseconds,
    required this.buildShouldRunMilliseconds,
    required this.trackedActionMilliseconds,
    required this.trackedActionWallMilliseconds,
    required this.trackedPhaseMilliseconds,
    required this.trackedBuilderActionCount,
    required this.trackedBuildPhaseCount,
    required this.assetGraphPersistMilliseconds,
    required this.cacheFlushMilliseconds,
    required this.resourceDisposeMilliseconds,
    required this.mergedOutputsMilliseconds,
    required this.resolverResetMilliseconds,
    required this.buildLogFinishMilliseconds,
    required this.assetGraphSerializeProbeMilliseconds,
    required this.assetGraphSerializeProbeBytes,
  });

  int get untrackedBuildRunMilliseconds =>
      math.max(0, buildRunMilliseconds - trackedActionMilliseconds);

  Map<String, Object?> toJson() => {
    'freshnessCheckMilliseconds': freshnessCheckMilliseconds,
    'configReloadMilliseconds': configReloadMilliseconds,
    'buildRunMilliseconds': buildRunMilliseconds,
    'assetGraphUpdateMilliseconds': assetGraphUpdateMilliseconds,
    'runPhasesMilliseconds': runPhasesMilliseconds,
    'phasedAssetDepsUpdateMilliseconds': phasedAssetDepsUpdateMilliseconds,
    'matchingPrimaryInputsMilliseconds': matchingPrimaryInputsMilliseconds,
    'buildShouldRunMilliseconds': buildShouldRunMilliseconds,
    'trackedActionMilliseconds': trackedActionMilliseconds,
    'trackedActionWallMilliseconds': trackedActionWallMilliseconds,
    'trackedPhaseMilliseconds': trackedPhaseMilliseconds,
    'trackedBuilderActionCount': trackedBuilderActionCount,
    'trackedBuildPhaseCount': trackedBuildPhaseCount,
    'assetGraphPersistMilliseconds': assetGraphPersistMilliseconds,
    'cacheFlushMilliseconds': cacheFlushMilliseconds,
    'resourceDisposeMilliseconds': resourceDisposeMilliseconds,
    'mergedOutputsMilliseconds': mergedOutputsMilliseconds,
    'resolverResetMilliseconds': resolverResetMilliseconds,
    'buildLogFinishMilliseconds': buildLogFinishMilliseconds,
    'assetGraphSerializeProbeMilliseconds': assetGraphSerializeProbeMilliseconds,
    'assetGraphSerializeProbeBytes': assetGraphSerializeProbeBytes,
    'untrackedBuildRunMilliseconds': untrackedBuildRunMilliseconds,
  };

  static FastBuildRunProfile fromJson(Map<String, Object?> json) =>
      FastBuildRunProfile(
        freshnessCheckMilliseconds: json['freshnessCheckMilliseconds']! as int,
        configReloadMilliseconds: json['configReloadMilliseconds']! as int,
        buildRunMilliseconds: json['buildRunMilliseconds']! as int,
        assetGraphUpdateMilliseconds:
            json['assetGraphUpdateMilliseconds']! as int,
        runPhasesMilliseconds: json['runPhasesMilliseconds']! as int,
        phasedAssetDepsUpdateMilliseconds:
            json['phasedAssetDepsUpdateMilliseconds']! as int,
        matchingPrimaryInputsMilliseconds:
            json['matchingPrimaryInputsMilliseconds']! as int,
        buildShouldRunMilliseconds: json['buildShouldRunMilliseconds']! as int,
        trackedActionMilliseconds: json['trackedActionMilliseconds']! as int,
        trackedActionWallMilliseconds:
            json['trackedActionWallMilliseconds']! as int,
        trackedPhaseMilliseconds: json['trackedPhaseMilliseconds']! as int,
        trackedBuilderActionCount: json['trackedBuilderActionCount']! as int,
        trackedBuildPhaseCount: json['trackedBuildPhaseCount']! as int,
        assetGraphPersistMilliseconds:
            json['assetGraphPersistMilliseconds']! as int,
        cacheFlushMilliseconds: json['cacheFlushMilliseconds']! as int,
        resourceDisposeMilliseconds:
            json['resourceDisposeMilliseconds']! as int,
        mergedOutputsMilliseconds: json['mergedOutputsMilliseconds']! as int,
        resolverResetMilliseconds:
            json['resolverResetMilliseconds']! as int,
        buildLogFinishMilliseconds:
            json['buildLogFinishMilliseconds']! as int,
        assetGraphSerializeProbeMilliseconds:
            json['assetGraphSerializeProbeMilliseconds']! as int,
        assetGraphSerializeProbeBytes:
            json['assetGraphSerializeProbeBytes']! as int,
      );

  factory FastBuildRunProfile.fromBuildResult({
    required BuildResult buildResult,
    required int freshnessCheckMilliseconds,
    required int configReloadMilliseconds,
    required int buildRunMilliseconds,
    required int assetGraphUpdateMilliseconds,
    required int runPhasesMilliseconds,
    required int phasedAssetDepsUpdateMilliseconds,
    required int matchingPrimaryInputsMilliseconds,
    required int buildShouldRunMilliseconds,
    required int assetGraphPersistMilliseconds,
    required int cacheFlushMilliseconds,
    required int resourceDisposeMilliseconds,
    required int mergedOutputsMilliseconds,
    required int resolverResetMilliseconds,
    required int buildLogFinishMilliseconds,
    required int assetGraphSerializeProbeMilliseconds,
    required int assetGraphSerializeProbeBytes,
  }) {
    final performance = buildResult.performance;
    if (performance == null) {
      return _withoutTrackedPerformance(
        freshnessCheckMilliseconds: freshnessCheckMilliseconds,
        configReloadMilliseconds: configReloadMilliseconds,
        buildRunMilliseconds: buildRunMilliseconds,
        assetGraphUpdateMilliseconds: assetGraphUpdateMilliseconds,
        runPhasesMilliseconds: runPhasesMilliseconds,
        phasedAssetDepsUpdateMilliseconds: phasedAssetDepsUpdateMilliseconds,
        matchingPrimaryInputsMilliseconds: matchingPrimaryInputsMilliseconds,
        buildShouldRunMilliseconds: buildShouldRunMilliseconds,
        assetGraphPersistMilliseconds: assetGraphPersistMilliseconds,
        cacheFlushMilliseconds: cacheFlushMilliseconds,
        resourceDisposeMilliseconds: resourceDisposeMilliseconds,
        mergedOutputsMilliseconds: mergedOutputsMilliseconds,
        resolverResetMilliseconds: resolverResetMilliseconds,
        buildLogFinishMilliseconds: buildLogFinishMilliseconds,
        assetGraphSerializeProbeMilliseconds:
            assetGraphSerializeProbeMilliseconds,
        assetGraphSerializeProbeBytes: assetGraphSerializeProbeBytes,
      );
    }

    try {
      var trackedActionMilliseconds = 0;
      var trackedActionWallMilliseconds = 0;
      for (final action in performance.actions) {
        trackedActionMilliseconds += action.innerDuration.inMilliseconds;
        trackedActionWallMilliseconds += action.duration.inMilliseconds;
      }

      var trackedPhaseMilliseconds = 0;
      for (final phase in performance.phases) {
        trackedPhaseMilliseconds += phase.duration.inMilliseconds;
      }

      return FastBuildRunProfile(
        freshnessCheckMilliseconds: freshnessCheckMilliseconds,
        configReloadMilliseconds: configReloadMilliseconds,
        buildRunMilliseconds: buildRunMilliseconds,
        assetGraphUpdateMilliseconds: assetGraphUpdateMilliseconds,
        runPhasesMilliseconds: runPhasesMilliseconds,
        phasedAssetDepsUpdateMilliseconds: phasedAssetDepsUpdateMilliseconds,
        matchingPrimaryInputsMilliseconds: matchingPrimaryInputsMilliseconds,
        buildShouldRunMilliseconds: buildShouldRunMilliseconds,
        trackedActionMilliseconds: trackedActionMilliseconds,
        trackedActionWallMilliseconds: trackedActionWallMilliseconds,
        trackedPhaseMilliseconds: trackedPhaseMilliseconds,
        trackedBuilderActionCount: performance.actions.length,
        trackedBuildPhaseCount: performance.phases.length,
        assetGraphPersistMilliseconds: assetGraphPersistMilliseconds,
        cacheFlushMilliseconds: cacheFlushMilliseconds,
        resourceDisposeMilliseconds: resourceDisposeMilliseconds,
        mergedOutputsMilliseconds: mergedOutputsMilliseconds,
        resolverResetMilliseconds: resolverResetMilliseconds,
        buildLogFinishMilliseconds: buildLogFinishMilliseconds,
        assetGraphSerializeProbeMilliseconds: assetGraphSerializeProbeMilliseconds,
        assetGraphSerializeProbeBytes: assetGraphSerializeProbeBytes,
      );
    } on UnsupportedError {
      return _withoutTrackedPerformance(
        freshnessCheckMilliseconds: freshnessCheckMilliseconds,
        configReloadMilliseconds: configReloadMilliseconds,
        buildRunMilliseconds: buildRunMilliseconds,
        assetGraphUpdateMilliseconds: assetGraphUpdateMilliseconds,
        runPhasesMilliseconds: runPhasesMilliseconds,
        phasedAssetDepsUpdateMilliseconds: phasedAssetDepsUpdateMilliseconds,
        matchingPrimaryInputsMilliseconds: matchingPrimaryInputsMilliseconds,
        buildShouldRunMilliseconds: buildShouldRunMilliseconds,
        assetGraphPersistMilliseconds: assetGraphPersistMilliseconds,
        cacheFlushMilliseconds: cacheFlushMilliseconds,
        resourceDisposeMilliseconds: resourceDisposeMilliseconds,
        mergedOutputsMilliseconds: mergedOutputsMilliseconds,
        resolverResetMilliseconds: resolverResetMilliseconds,
        buildLogFinishMilliseconds: buildLogFinishMilliseconds,
        assetGraphSerializeProbeMilliseconds: assetGraphSerializeProbeMilliseconds,
        assetGraphSerializeProbeBytes: assetGraphSerializeProbeBytes,
      );
    }
  }

  static FastBuildRunProfile _withoutTrackedPerformance({
    required int freshnessCheckMilliseconds,
    required int configReloadMilliseconds,
    required int buildRunMilliseconds,
    required int assetGraphUpdateMilliseconds,
    required int runPhasesMilliseconds,
    required int phasedAssetDepsUpdateMilliseconds,
    required int matchingPrimaryInputsMilliseconds,
    required int buildShouldRunMilliseconds,
    required int assetGraphPersistMilliseconds,
    required int cacheFlushMilliseconds,
    required int resourceDisposeMilliseconds,
    required int mergedOutputsMilliseconds,
    required int resolverResetMilliseconds,
    required int buildLogFinishMilliseconds,
    required int assetGraphSerializeProbeMilliseconds,
    required int assetGraphSerializeProbeBytes,
  }) {
    return FastBuildRunProfile(
      freshnessCheckMilliseconds: freshnessCheckMilliseconds,
      configReloadMilliseconds: configReloadMilliseconds,
      buildRunMilliseconds: buildRunMilliseconds,
      assetGraphUpdateMilliseconds: assetGraphUpdateMilliseconds,
      runPhasesMilliseconds: runPhasesMilliseconds,
      phasedAssetDepsUpdateMilliseconds: phasedAssetDepsUpdateMilliseconds,
      matchingPrimaryInputsMilliseconds: matchingPrimaryInputsMilliseconds,
      buildShouldRunMilliseconds: buildShouldRunMilliseconds,
      trackedActionMilliseconds: 0,
      trackedActionWallMilliseconds: 0,
      trackedPhaseMilliseconds: 0,
      trackedBuilderActionCount: 0,
      trackedBuildPhaseCount: 0,
      assetGraphPersistMilliseconds: assetGraphPersistMilliseconds,
      cacheFlushMilliseconds: cacheFlushMilliseconds,
      resourceDisposeMilliseconds: resourceDisposeMilliseconds,
      mergedOutputsMilliseconds: mergedOutputsMilliseconds,
      resolverResetMilliseconds: resolverResetMilliseconds,
      buildLogFinishMilliseconds: buildLogFinishMilliseconds,
      assetGraphSerializeProbeMilliseconds: assetGraphSerializeProbeMilliseconds,
      assetGraphSerializeProbeBytes: assetGraphSerializeProbeBytes,
    );
  }
}

class FastBuildRunOutcome {
  final BuildResult result;
  final FastBuildRunProfile profile;

  const FastBuildRunOutcome({required this.result, required this.profile});
}
