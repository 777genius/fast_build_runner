// ignore_for_file: implementation_imports, experimental_member_use

import 'dart:math' as math;

import 'package:build_runner/src/build/build_result.dart';

class FastBuildRunProfile {
  final int freshnessCheckMilliseconds;
  final int configReloadMilliseconds;
  final int buildRunMilliseconds;
  final int trackedActionMilliseconds;
  final int trackedPhaseMilliseconds;
  final int trackedBuilderActionCount;
  final int trackedBuildPhaseCount;

  const FastBuildRunProfile({
    required this.freshnessCheckMilliseconds,
    required this.configReloadMilliseconds,
    required this.buildRunMilliseconds,
    required this.trackedActionMilliseconds,
    required this.trackedPhaseMilliseconds,
    required this.trackedBuilderActionCount,
    required this.trackedBuildPhaseCount,
  });

  int get untrackedBuildRunMilliseconds =>
      math.max(0, buildRunMilliseconds - trackedActionMilliseconds);

  Map<String, Object?> toJson() => {
    'freshnessCheckMilliseconds': freshnessCheckMilliseconds,
    'configReloadMilliseconds': configReloadMilliseconds,
    'buildRunMilliseconds': buildRunMilliseconds,
    'trackedActionMilliseconds': trackedActionMilliseconds,
    'trackedPhaseMilliseconds': trackedPhaseMilliseconds,
    'trackedBuilderActionCount': trackedBuilderActionCount,
    'trackedBuildPhaseCount': trackedBuildPhaseCount,
    'untrackedBuildRunMilliseconds': untrackedBuildRunMilliseconds,
  };

  static FastBuildRunProfile fromJson(Map<String, Object?> json) =>
      FastBuildRunProfile(
        freshnessCheckMilliseconds: json['freshnessCheckMilliseconds']! as int,
        configReloadMilliseconds: json['configReloadMilliseconds']! as int,
        buildRunMilliseconds: json['buildRunMilliseconds']! as int,
        trackedActionMilliseconds: json['trackedActionMilliseconds']! as int,
        trackedPhaseMilliseconds: json['trackedPhaseMilliseconds']! as int,
        trackedBuilderActionCount: json['trackedBuilderActionCount']! as int,
        trackedBuildPhaseCount: json['trackedBuildPhaseCount']! as int,
      );

  factory FastBuildRunProfile.fromBuildResult({
    required BuildResult buildResult,
    required int freshnessCheckMilliseconds,
    required int configReloadMilliseconds,
    required int buildRunMilliseconds,
  }) {
    final performance = buildResult.performance;
    if (performance == null) {
      return _withoutTrackedPerformance(
        freshnessCheckMilliseconds: freshnessCheckMilliseconds,
        configReloadMilliseconds: configReloadMilliseconds,
        buildRunMilliseconds: buildRunMilliseconds,
      );
    }

    try {
      var trackedActionMilliseconds = 0;
      for (final action in performance.actions) {
        trackedActionMilliseconds += action.innerDuration.inMilliseconds;
      }

      var trackedPhaseMilliseconds = 0;
      for (final phase in performance.phases) {
        trackedPhaseMilliseconds += phase.duration.inMilliseconds;
      }

      return FastBuildRunProfile(
        freshnessCheckMilliseconds: freshnessCheckMilliseconds,
        configReloadMilliseconds: configReloadMilliseconds,
        buildRunMilliseconds: buildRunMilliseconds,
        trackedActionMilliseconds: trackedActionMilliseconds,
        trackedPhaseMilliseconds: trackedPhaseMilliseconds,
        trackedBuilderActionCount: performance.actions.length,
        trackedBuildPhaseCount: performance.phases.length,
      );
    } on UnsupportedError {
      return _withoutTrackedPerformance(
        freshnessCheckMilliseconds: freshnessCheckMilliseconds,
        configReloadMilliseconds: configReloadMilliseconds,
        buildRunMilliseconds: buildRunMilliseconds,
      );
    }
  }

  static FastBuildRunProfile _withoutTrackedPerformance({
    required int freshnessCheckMilliseconds,
    required int configReloadMilliseconds,
    required int buildRunMilliseconds,
  }) {
    return FastBuildRunProfile(
      freshnessCheckMilliseconds: freshnessCheckMilliseconds,
      configReloadMilliseconds: configReloadMilliseconds,
      buildRunMilliseconds: buildRunMilliseconds,
      trackedActionMilliseconds: 0,
      trackedPhaseMilliseconds: 0,
      trackedBuilderActionCount: 0,
      trackedBuildPhaseCount: 0,
    );
  }
}

class FastBuildRunOutcome {
  final BuildResult result;
  final FastBuildRunProfile profile;

  const FastBuildRunOutcome({required this.result, required this.profile});
}
