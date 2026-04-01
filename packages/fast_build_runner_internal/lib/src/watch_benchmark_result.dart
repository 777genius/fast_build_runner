import 'bootstrap_spike_result.dart';
import 'watch_alpha_result.dart';

class FastWatchBenchmarkEngineResult {
  final String sourceEngine;
  final int elapsedMilliseconds;
  final FastWatchAlphaResult result;

  const FastWatchBenchmarkEngineResult({
    required this.sourceEngine,
    required this.elapsedMilliseconds,
    required this.result,
  });

  Map<String, Object?> toJson() => {
    'sourceEngine': sourceEngine,
    'elapsedMilliseconds': elapsedMilliseconds,
    'result': result.toJson(),
  };

  static FastWatchBenchmarkEngineResult fromJson(Map<String, Object?> json) =>
      FastWatchBenchmarkEngineResult(
        sourceEngine: json['sourceEngine']! as String,
        elapsedMilliseconds: json['elapsedMilliseconds']! as int,
        result: FastWatchAlphaResult.fromJson(
          Map<String, Object?>.from(json['result']! as Map),
        ),
      );
}

class FastWatchBenchmarkResult {
  final String status;
  final int incrementalCycles;
  final int repeats;
  final int noiseFilesPerCycle;
  final bool continuousScheduling;
  final int extraFixtureModels;
  final int settleBuildDelayMs;
  final bool trustBuildScriptFreshness;
  final FastWatchBenchmarkEngineResult? upstream;
  final FastWatchBenchmarkEngineResult dart;
  final FastWatchBenchmarkEngineResult rust;
  final List<FastWatchBenchmarkEngineResult> upstreamSamples;
  final List<FastWatchBenchmarkEngineResult> dartSamples;
  final List<FastWatchBenchmarkEngineResult> rustSamples;
  final double? rustSpeedupVsDart;
  final double? rustSpeedupVsUpstream;
  final double? dartSpeedupVsUpstream;
  final List<String> warnings;
  final List<String> errors;

  const FastWatchBenchmarkResult({
    required this.status,
    required this.incrementalCycles,
    required this.repeats,
    required this.noiseFilesPerCycle,
    required this.continuousScheduling,
    required this.extraFixtureModels,
    required this.settleBuildDelayMs,
    required this.trustBuildScriptFreshness,
    required this.upstream,
    required this.dart,
    required this.rust,
    required this.upstreamSamples,
    required this.dartSamples,
    required this.rustSamples,
    required this.rustSpeedupVsDart,
    required this.rustSpeedupVsUpstream,
    required this.dartSpeedupVsUpstream,
    required this.warnings,
    required this.errors,
  });

  factory FastWatchBenchmarkResult.fromRuns({
    required int incrementalCycles,
    required int noiseFilesPerCycle,
    required bool continuousScheduling,
    required int extraFixtureModels,
    required int settleBuildDelayMs,
    required bool trustBuildScriptFreshness,
    List<FastWatchBenchmarkEngineResult> upstreamSamples = const [],
    required List<FastWatchBenchmarkEngineResult> dartSamples,
    required List<FastWatchBenchmarkEngineResult> rustSamples,
  }) {
    if (dartSamples.isEmpty || rustSamples.isEmpty) {
      throw StateError('Benchmark samples must not be empty.');
    }
    final upstream = upstreamSamples.isEmpty
        ? null
        : _medianSample(upstreamSamples);
    final dart = _medianSample(dartSamples);
    final rust = _medianSample(rustSamples);
    final rustSpeedupVsDart = rust.elapsedMilliseconds > 0
        ? dart.elapsedMilliseconds / rust.elapsedMilliseconds
        : null;
    final rustSpeedupVsUpstream =
        upstream != null && rust.elapsedMilliseconds > 0
        ? upstream.elapsedMilliseconds / rust.elapsedMilliseconds
        : null;
    final dartSpeedupVsUpstream =
        upstream != null && dart.elapsedMilliseconds > 0
        ? upstream.elapsedMilliseconds / dart.elapsedMilliseconds
        : null;
    final rustIncrementalBuildSpeedupVsDart =
        dart.result.incrementalBuild != null &&
            rust.result.incrementalBuild != null &&
            rust.result.incrementalBuild!.elapsedMilliseconds > 0
        ? dart.result.incrementalBuild!.elapsedMilliseconds /
              rust.result.incrementalBuild!.elapsedMilliseconds
        : null;

    final warnings = <String>[
      if (rustSpeedupVsDart != null)
        'Rust source engine speedup vs dart source engine: ${rustSpeedupVsDart.toStringAsFixed(2)}x',
      if (rustSpeedupVsUpstream != null)
        'fast_build_runner (rust source engine) speedup vs upstream watch: ${rustSpeedupVsUpstream.toStringAsFixed(2)}x',
      if (dartSpeedupVsUpstream != null)
        'fast_build_runner (dart source engine) speedup vs upstream watch: ${dartSpeedupVsUpstream.toStringAsFixed(2)}x',
      if (rustIncrementalBuildSpeedupVsDart != null &&
          rustSpeedupVsDart != null &&
          rustIncrementalBuildSpeedupVsDart > rustSpeedupVsDart + 0.1)
        'Incremental build speedup is stronger than total wall-clock speedup, which suggests initial build cost still dominates this fixture.',
      if (noiseFilesPerCycle > 0)
        'Each watch cycle injected $noiseFilesPerCycle unrelated filesystem noise file(s) before batch collection.',
      if (continuousScheduling)
        'Continuous scheduling stayed subscribed to watch batches while builds were in flight.',
      if (settleBuildDelayMs > 0)
        'A post-build settle window of ${settleBuildDelayMs}ms was used to coalesce bursty updates.',
      if (trustBuildScriptFreshness)
        'Experimental mode trusted the bootstrapped build script freshness on incremental runs.',
      if (extraFixtureModels > 0)
        'The copied benchmark fixture was expanded with $extraFixtureModels extra json_serializable model(s).',
      if (_incrementalProfileMetric(
                dart.result.incrementalBuild?.profile,
                'untrackedBuildRunMilliseconds',
              ) !=
              null &&
          _incrementalProfileMetric(
                dart.result.incrementalBuild?.profile,
                'trackedActionWallMilliseconds',
              ) !=
              null &&
          _incrementalProfileMetric(
                dart.result.incrementalBuild?.profile,
                'untrackedBuildRunMilliseconds',
              )! >
              _incrementalProfileMetric(
                dart.result.incrementalBuild?.profile,
                'trackedActionWallMilliseconds',
              )!)
        'The dart incremental build still spends more time outside tracked action wall-clock than inside tracked builder actions.',
      if (_incrementalProfileMetric(
                rust.result.incrementalBuild?.profile,
                'untrackedBuildRunMilliseconds',
              ) !=
              null &&
          _incrementalProfileMetric(
                rust.result.incrementalBuild?.profile,
                'trackedActionWallMilliseconds',
              ) !=
              null &&
          _incrementalProfileMetric(
                rust.result.incrementalBuild?.profile,
                'untrackedBuildRunMilliseconds',
              )! >
              _incrementalProfileMetric(
                rust.result.incrementalBuild?.profile,
                'trackedActionWallMilliseconds',
              )!)
        'The rust incremental build still spends more time outside tracked action wall-clock than inside tracked builder actions.',
    ];
    final errors = <String>[
      if (upstream != null && !upstream.result.isSuccess)
        'Upstream benchmark run failed: ${upstream.result.errors.join(' | ')}',
      if (!dart.result.isSuccess)
        'Dart benchmark run failed: ${dart.result.errors.join(' | ')}',
      if (!rust.result.isSuccess)
        'Rust benchmark run failed: ${rust.result.errors.join(' | ')}',
    ];

    return FastWatchBenchmarkResult(
      status: errors.isEmpty ? 'success' : 'failure',
      incrementalCycles: incrementalCycles,
      repeats: _minSampleCount(upstreamSamples, dartSamples, rustSamples),
      noiseFilesPerCycle: noiseFilesPerCycle,
      continuousScheduling: continuousScheduling,
      extraFixtureModels: extraFixtureModels,
      settleBuildDelayMs: settleBuildDelayMs,
      trustBuildScriptFreshness: trustBuildScriptFreshness,
      upstream: upstream,
      dart: dart,
      rust: rust,
      upstreamSamples: upstreamSamples,
      dartSamples: dartSamples,
      rustSamples: rustSamples,
      rustSpeedupVsDart: rustSpeedupVsDart,
      rustSpeedupVsUpstream: rustSpeedupVsUpstream,
      dartSpeedupVsUpstream: dartSpeedupVsUpstream,
      warnings: warnings,
      errors: errors,
    );
  }

  bool get isSuccess => status == 'success';
  int get exitCode => isSuccess ? 0 : 1;

  double? get rustInitialBuildSpeedupVsUpstream {
    final upstreamInitial = upstream?.result.initialBuild?.elapsedMilliseconds;
    final rustInitial = rust.result.initialBuild?.elapsedMilliseconds;
    if (upstreamInitial == null || rustInitial == null || rustInitial == 0) {
      return null;
    }
    return upstreamInitial / rustInitial;
  }

  double? get rustInitialBuildSpeedupVsDart {
    final dartInitial = dart.result.initialBuild?.elapsedMilliseconds;
    final rustInitial = rust.result.initialBuild?.elapsedMilliseconds;
    if (dartInitial == null || rustInitial == null || rustInitial == 0) {
      return null;
    }
    return dartInitial / rustInitial;
  }

  int? get upstreamTotalIncrementalBuildMilliseconds =>
      _totalIncrementalBuildMilliseconds(upstream?.result.incrementalBuilds);

  int? get dartTotalIncrementalBuildMilliseconds =>
      _totalIncrementalBuildMilliseconds(dart.result.incrementalBuilds);

  int? get rustTotalIncrementalBuildMilliseconds =>
      _totalIncrementalBuildMilliseconds(rust.result.incrementalBuilds);

  double? get rustTotalIncrementalBuildSpeedupVsUpstream {
    final upstreamTotal = upstreamTotalIncrementalBuildMilliseconds;
    final rustTotal = rustTotalIncrementalBuildMilliseconds;
    if (upstreamTotal == null || rustTotal == null || rustTotal == 0) {
      return null;
    }
    return upstreamTotal / rustTotal;
  }

  double? get rustTotalIncrementalBuildSpeedupVsDart {
    final dartTotal = dartTotalIncrementalBuildMilliseconds;
    final rustTotal = rustTotalIncrementalBuildMilliseconds;
    if (dartTotal == null || rustTotal == null || rustTotal == 0) {
      return null;
    }
    return dartTotal / rustTotal;
  }

  double? get rustIncrementalBuildSpeedupVsUpstream {
    final upstreamIncremental =
        upstream?.result.incrementalBuild?.elapsedMilliseconds;
    final rustIncremental = rust.result.incrementalBuild?.elapsedMilliseconds;
    if (upstreamIncremental == null ||
        rustIncremental == null ||
        rustIncremental == 0) {
      return null;
    }
    return upstreamIncremental / rustIncremental;
  }

  double? get rustIncrementalBuildSpeedupVsDart {
    final dartIncremental = dart.result.incrementalBuild?.elapsedMilliseconds;
    final rustIncremental = rust.result.incrementalBuild?.elapsedMilliseconds;
    if (dartIncremental == null ||
        rustIncremental == null ||
        rustIncremental == 0) {
      return null;
    }
    return dartIncremental / rustIncremental;
  }

  double? get rustWatchCollectionSpeedupVsDart {
    final dartWatchCollection = dart.result.watchCollectionMilliseconds;
    final rustWatchCollection = rust.result.watchCollectionMilliseconds;
    if (dartWatchCollection.isEmpty || rustWatchCollection.isEmpty) {
      return null;
    }
    final dartTotal = dartWatchCollection.reduce((a, b) => a + b);
    final rustTotal = rustWatchCollection.reduce((a, b) => a + b);
    if (rustTotal == 0) {
      return null;
    }
    return dartTotal / rustTotal;
  }

  int? get dartIncrementalTrackedActionMilliseconds =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'trackedActionMilliseconds',
      );

  int? get dartIncrementalAssetGraphUpdateMilliseconds =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'assetGraphUpdateMilliseconds',
      );

  int? get rustIncrementalAssetGraphUpdateMilliseconds =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'assetGraphUpdateMilliseconds',
      );

  int? get dartIncrementalRunPhasesMilliseconds =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'runPhasesMilliseconds',
      );

  int? get rustIncrementalRunPhasesMilliseconds =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'runPhasesMilliseconds',
      );

  int? get dartIncrementalPhasedAssetDepsUpdateMilliseconds =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'phasedAssetDepsUpdateMilliseconds',
      );

  int? get rustIncrementalPhasedAssetDepsUpdateMilliseconds =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'phasedAssetDepsUpdateMilliseconds',
      );

  int? get dartIncrementalMatchingPrimaryInputsMilliseconds =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'matchingPrimaryInputsMilliseconds',
      );

  int? get rustIncrementalMatchingPrimaryInputsMilliseconds =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'matchingPrimaryInputsMilliseconds',
      );

  int? get dartIncrementalBuildShouldRunMilliseconds =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'buildShouldRunMilliseconds',
      );

  int? get rustIncrementalBuildShouldRunMilliseconds =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'buildShouldRunMilliseconds',
      );

  int? get rustIncrementalTrackedActionMilliseconds =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'trackedActionMilliseconds',
      );

  int? get dartIncrementalTrackedActionWallMilliseconds =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'trackedActionWallMilliseconds',
      );

  int? get rustIncrementalTrackedActionWallMilliseconds =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'trackedActionWallMilliseconds',
      );

  int? get dartIncrementalUntrackedBuildMilliseconds =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'untrackedBuildRunMilliseconds',
      );

  int? get rustIncrementalUntrackedBuildMilliseconds =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'untrackedBuildRunMilliseconds',
      );

  int? get dartIncrementalFreshnessCheckMilliseconds =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'freshnessCheckMilliseconds',
      );

  int? get rustIncrementalFreshnessCheckMilliseconds =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'freshnessCheckMilliseconds',
      );

  int? get dartIncrementalConfigReloadMilliseconds =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'configReloadMilliseconds',
      );

  int? get rustIncrementalConfigReloadMilliseconds =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'configReloadMilliseconds',
      );

  int? get dartIncrementalAssetGraphSerializeProbeMilliseconds =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'assetGraphSerializeProbeMilliseconds',
      );

  int? get rustIncrementalAssetGraphSerializeProbeMilliseconds =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'assetGraphSerializeProbeMilliseconds',
      );

  int? get dartIncrementalAssetGraphSerializeProbeBytes =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'assetGraphSerializeProbeBytes',
      );

  int? get rustIncrementalAssetGraphSerializeProbeBytes =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'assetGraphSerializeProbeBytes',
      );

  int? get dartIncrementalAssetGraphPersistMilliseconds =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'assetGraphPersistMilliseconds',
      );

  int? get rustIncrementalAssetGraphPersistMilliseconds =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'assetGraphPersistMilliseconds',
      );

  int? get dartIncrementalCacheFlushMilliseconds =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'cacheFlushMilliseconds',
      );

  int? get rustIncrementalCacheFlushMilliseconds =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'cacheFlushMilliseconds',
      );

  int? get dartIncrementalResourceDisposeMilliseconds =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'resourceDisposeMilliseconds',
      );

  int? get rustIncrementalResourceDisposeMilliseconds =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'resourceDisposeMilliseconds',
      );

  int? get dartIncrementalMergedOutputsMilliseconds =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'mergedOutputsMilliseconds',
      );

  int? get rustIncrementalMergedOutputsMilliseconds =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'mergedOutputsMilliseconds',
      );

  int? get dartIncrementalResolverResetMilliseconds =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'resolverResetMilliseconds',
      );

  int? get rustIncrementalResolverResetMilliseconds =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'resolverResetMilliseconds',
      );

  int? get dartIncrementalBuildLogFinishMilliseconds =>
      _incrementalProfileMetric(
        dart.result.incrementalBuild?.profile,
        'buildLogFinishMilliseconds',
      );

  int? get rustIncrementalBuildLogFinishMilliseconds =>
      _incrementalProfileMetric(
        rust.result.incrementalBuild?.profile,
        'buildLogFinishMilliseconds',
      );

  static int? _incrementalProfileMetric(
    Map<String, Object?>? profile,
    String key,
  ) {
    final value = profile?[key];
    return value is int ? value : null;
  }

  int? get dartTotalWatchCollectionMilliseconds =>
      _totalCollectionMilliseconds(dart.result.watchCollectionMilliseconds);

  int? get rustTotalWatchCollectionMilliseconds =>
      _totalCollectionMilliseconds(rust.result.watchCollectionMilliseconds);

  Map<String, Object?> toJson() => {
    'status': status,
    'incrementalCycles': incrementalCycles,
    'repeats': repeats,
    'noiseFilesPerCycle': noiseFilesPerCycle,
    'continuousScheduling': continuousScheduling,
    'extraFixtureModels': extraFixtureModels,
    'settleBuildDelayMs': settleBuildDelayMs,
    'trustBuildScriptFreshness': trustBuildScriptFreshness,
    'upstream': upstream?.toJson(),
    'dart': dart.toJson(),
    'rust': rust.toJson(),
    'upstreamSamples': upstreamSamples
        .map((sample) => sample.toJson())
        .toList(),
    'dartSamples': dartSamples.map((sample) => sample.toJson()).toList(),
    'rustSamples': rustSamples.map((sample) => sample.toJson()).toList(),
    'rustSpeedupVsDart': rustSpeedupVsDart,
    'rustSpeedupVsUpstream': rustSpeedupVsUpstream,
    'dartSpeedupVsUpstream': dartSpeedupVsUpstream,
    'rustInitialBuildSpeedupVsUpstream': rustInitialBuildSpeedupVsUpstream,
    'rustInitialBuildSpeedupVsDart': rustInitialBuildSpeedupVsDart,
    'upstreamTotalIncrementalBuildMilliseconds':
        upstreamTotalIncrementalBuildMilliseconds,
    'dartTotalIncrementalBuildMilliseconds':
        dartTotalIncrementalBuildMilliseconds,
    'rustTotalIncrementalBuildMilliseconds':
        rustTotalIncrementalBuildMilliseconds,
    'rustTotalIncrementalBuildSpeedupVsUpstream':
        rustTotalIncrementalBuildSpeedupVsUpstream,
    'rustTotalIncrementalBuildSpeedupVsDart':
        rustTotalIncrementalBuildSpeedupVsDart,
    'rustIncrementalBuildSpeedupVsUpstream':
        rustIncrementalBuildSpeedupVsUpstream,
    'rustIncrementalBuildSpeedupVsDart': rustIncrementalBuildSpeedupVsDart,
    'rustWatchCollectionSpeedupVsDart': rustWatchCollectionSpeedupVsDart,
    'dartIncrementalTrackedActionMilliseconds':
        dartIncrementalTrackedActionMilliseconds,
    'rustIncrementalTrackedActionMilliseconds':
        rustIncrementalTrackedActionMilliseconds,
    'dartIncrementalTrackedActionWallMilliseconds':
        dartIncrementalTrackedActionWallMilliseconds,
    'rustIncrementalTrackedActionWallMilliseconds':
        rustIncrementalTrackedActionWallMilliseconds,
    'dartIncrementalAssetGraphUpdateMilliseconds':
        dartIncrementalAssetGraphUpdateMilliseconds,
    'rustIncrementalAssetGraphUpdateMilliseconds':
        rustIncrementalAssetGraphUpdateMilliseconds,
    'dartIncrementalRunPhasesMilliseconds':
        dartIncrementalRunPhasesMilliseconds,
    'rustIncrementalRunPhasesMilliseconds':
        rustIncrementalRunPhasesMilliseconds,
    'dartIncrementalPhasedAssetDepsUpdateMilliseconds':
        dartIncrementalPhasedAssetDepsUpdateMilliseconds,
    'rustIncrementalPhasedAssetDepsUpdateMilliseconds':
        rustIncrementalPhasedAssetDepsUpdateMilliseconds,
    'dartIncrementalMatchingPrimaryInputsMilliseconds':
        dartIncrementalMatchingPrimaryInputsMilliseconds,
    'rustIncrementalMatchingPrimaryInputsMilliseconds':
        rustIncrementalMatchingPrimaryInputsMilliseconds,
    'dartIncrementalBuildShouldRunMilliseconds':
        dartIncrementalBuildShouldRunMilliseconds,
    'rustIncrementalBuildShouldRunMilliseconds':
        rustIncrementalBuildShouldRunMilliseconds,
    'dartIncrementalFreshnessCheckMilliseconds':
        dartIncrementalFreshnessCheckMilliseconds,
    'rustIncrementalFreshnessCheckMilliseconds':
        rustIncrementalFreshnessCheckMilliseconds,
    'dartIncrementalConfigReloadMilliseconds':
        dartIncrementalConfigReloadMilliseconds,
    'rustIncrementalConfigReloadMilliseconds':
        rustIncrementalConfigReloadMilliseconds,
    'dartIncrementalUntrackedBuildMilliseconds':
        dartIncrementalUntrackedBuildMilliseconds,
    'rustIncrementalUntrackedBuildMilliseconds':
        rustIncrementalUntrackedBuildMilliseconds,
    'dartIncrementalAssetGraphSerializeProbeMilliseconds':
        dartIncrementalAssetGraphSerializeProbeMilliseconds,
    'rustIncrementalAssetGraphSerializeProbeMilliseconds':
        rustIncrementalAssetGraphSerializeProbeMilliseconds,
    'dartIncrementalAssetGraphSerializeProbeBytes':
        dartIncrementalAssetGraphSerializeProbeBytes,
    'rustIncrementalAssetGraphSerializeProbeBytes':
        rustIncrementalAssetGraphSerializeProbeBytes,
    'dartIncrementalAssetGraphPersistMilliseconds':
        dartIncrementalAssetGraphPersistMilliseconds,
    'rustIncrementalAssetGraphPersistMilliseconds':
        rustIncrementalAssetGraphPersistMilliseconds,
    'dartIncrementalCacheFlushMilliseconds':
        dartIncrementalCacheFlushMilliseconds,
    'rustIncrementalCacheFlushMilliseconds':
        rustIncrementalCacheFlushMilliseconds,
    'dartIncrementalResourceDisposeMilliseconds':
        dartIncrementalResourceDisposeMilliseconds,
    'rustIncrementalResourceDisposeMilliseconds':
        rustIncrementalResourceDisposeMilliseconds,
    'dartIncrementalMergedOutputsMilliseconds':
        dartIncrementalMergedOutputsMilliseconds,
    'rustIncrementalMergedOutputsMilliseconds':
        rustIncrementalMergedOutputsMilliseconds,
    'dartIncrementalResolverResetMilliseconds':
        dartIncrementalResolverResetMilliseconds,
    'rustIncrementalResolverResetMilliseconds':
        rustIncrementalResolverResetMilliseconds,
    'dartIncrementalBuildLogFinishMilliseconds':
        dartIncrementalBuildLogFinishMilliseconds,
    'rustIncrementalBuildLogFinishMilliseconds':
        rustIncrementalBuildLogFinishMilliseconds,
    'dartTotalWatchCollectionMilliseconds':
        dartTotalWatchCollectionMilliseconds,
    'rustTotalWatchCollectionMilliseconds':
        rustTotalWatchCollectionMilliseconds,
    'warnings': warnings,
    'errors': errors,
  };

  List<String> toSummaryLines() {
    final lines = <String>[
      'fast_build_runner watch benchmark',
      'status: $status',
      'incrementalCycles: $incrementalCycles',
      'repeats: $repeats',
      'noiseFilesPerCycle: $noiseFilesPerCycle',
      'continuousScheduling: $continuousScheduling',
      'extraFixtureModels: $extraFixtureModels',
      'settleBuildDelayMs: $settleBuildDelayMs',
      'trustBuildScriptFreshness: $trustBuildScriptFreshness',
      if (upstream != null) 'upstream: ${upstream!.elapsedMilliseconds} ms',
      'dart: ${dart.elapsedMilliseconds} ms',
      'rust: ${rust.elapsedMilliseconds} ms',
      if (upstreamSamples.length > 1)
        'upstreamSamples: ${upstreamSamples.map((sample) => sample.elapsedMilliseconds).join(', ')}',
      if (dartSamples.length > 1)
        'dartSamples: ${dartSamples.map((sample) => sample.elapsedMilliseconds).join(', ')}',
      if (rustSamples.length > 1)
        'rustSamples: ${rustSamples.map((sample) => sample.elapsedMilliseconds).join(', ')}',
      if (dart.result.initialBuild != null)
        'dartInitialBuild: ${dart.result.initialBuild!.elapsedMilliseconds} ms',
      if (rust.result.initialBuild != null)
        'rustInitialBuild: ${rust.result.initialBuild!.elapsedMilliseconds} ms',
      if (upstream?.result.incrementalBuild != null)
        'upstreamIncrementalBuild: ${upstream!.result.incrementalBuild!.elapsedMilliseconds} ms',
      if (dart.result.incrementalBuild != null)
        'dartIncrementalBuild: ${dart.result.incrementalBuild!.elapsedMilliseconds} ms',
      if (rust.result.incrementalBuild != null)
        'rustIncrementalBuild: ${rust.result.incrementalBuild!.elapsedMilliseconds} ms',
      if (upstreamTotalIncrementalBuildMilliseconds != null)
        'upstreamTotalIncrementalBuild: $upstreamTotalIncrementalBuildMilliseconds ms',
      if (dartTotalIncrementalBuildMilliseconds != null)
        'dartTotalIncrementalBuild: $dartTotalIncrementalBuildMilliseconds ms',
      if (rustTotalIncrementalBuildMilliseconds != null)
        'rustTotalIncrementalBuild: $rustTotalIncrementalBuildMilliseconds ms',
      if (dart.result.watchCollectionMilliseconds.isNotEmpty)
        'dartWatchCollection: ${dart.result.watchCollectionMilliseconds.join(', ')} ms',
      if (rust.result.watchCollectionMilliseconds.isNotEmpty)
        'rustWatchCollection: ${rust.result.watchCollectionMilliseconds.join(', ')} ms',
      if (dartTotalWatchCollectionMilliseconds != null)
        'dartTotalWatchCollection: $dartTotalWatchCollectionMilliseconds ms',
      if (rustTotalWatchCollectionMilliseconds != null)
        'rustTotalWatchCollection: $rustTotalWatchCollectionMilliseconds ms',
      if (rust.result.rustDaemonStartupMilliseconds != null)
        'rustDaemonStartup: ${rust.result.rustDaemonStartupMilliseconds} ms',
      if (rustInitialBuildSpeedupVsUpstream != null)
        'rustInitialBuildSpeedupVsUpstream: ${rustInitialBuildSpeedupVsUpstream!.toStringAsFixed(2)}x',
      if (rustInitialBuildSpeedupVsDart != null)
        'rustInitialBuildSpeedupVsDart: ${rustInitialBuildSpeedupVsDart!.toStringAsFixed(2)}x',
      if (rustIncrementalBuildSpeedupVsUpstream != null)
        'rustIncrementalBuildSpeedupVsUpstream: ${rustIncrementalBuildSpeedupVsUpstream!.toStringAsFixed(2)}x',
      if (rustIncrementalBuildSpeedupVsDart != null)
        'rustIncrementalBuildSpeedupVsDart: ${rustIncrementalBuildSpeedupVsDart!.toStringAsFixed(2)}x',
      if (rustTotalIncrementalBuildSpeedupVsUpstream != null)
        'rustTotalIncrementalBuildSpeedupVsUpstream: ${rustTotalIncrementalBuildSpeedupVsUpstream!.toStringAsFixed(2)}x',
      if (rustTotalIncrementalBuildSpeedupVsDart != null)
        'rustTotalIncrementalBuildSpeedupVsDart: ${rustTotalIncrementalBuildSpeedupVsDart!.toStringAsFixed(2)}x',
      if (dartIncrementalTrackedActionMilliseconds != null)
        'dartIncrementalTrackedActionMilliseconds: $dartIncrementalTrackedActionMilliseconds ms',
      if (rustIncrementalTrackedActionMilliseconds != null)
        'rustIncrementalTrackedActionMilliseconds: $rustIncrementalTrackedActionMilliseconds ms',
      if (dartIncrementalTrackedActionWallMilliseconds != null)
        'dartIncrementalTrackedActionWallMilliseconds: $dartIncrementalTrackedActionWallMilliseconds ms',
      if (rustIncrementalTrackedActionWallMilliseconds != null)
        'rustIncrementalTrackedActionWallMilliseconds: $rustIncrementalTrackedActionWallMilliseconds ms',
      if (dartIncrementalAssetGraphUpdateMilliseconds != null)
        'dartIncrementalAssetGraphUpdateMilliseconds: $dartIncrementalAssetGraphUpdateMilliseconds ms',
      if (rustIncrementalAssetGraphUpdateMilliseconds != null)
        'rustIncrementalAssetGraphUpdateMilliseconds: $rustIncrementalAssetGraphUpdateMilliseconds ms',
      if (dartIncrementalRunPhasesMilliseconds != null)
        'dartIncrementalRunPhasesMilliseconds: $dartIncrementalRunPhasesMilliseconds ms',
      if (rustIncrementalRunPhasesMilliseconds != null)
        'rustIncrementalRunPhasesMilliseconds: $rustIncrementalRunPhasesMilliseconds ms',
      if (dartIncrementalPhasedAssetDepsUpdateMilliseconds != null)
        'dartIncrementalPhasedAssetDepsUpdateMilliseconds: $dartIncrementalPhasedAssetDepsUpdateMilliseconds ms',
      if (rustIncrementalPhasedAssetDepsUpdateMilliseconds != null)
        'rustIncrementalPhasedAssetDepsUpdateMilliseconds: $rustIncrementalPhasedAssetDepsUpdateMilliseconds ms',
      if (dartIncrementalMatchingPrimaryInputsMilliseconds != null)
        'dartIncrementalMatchingPrimaryInputsMilliseconds: $dartIncrementalMatchingPrimaryInputsMilliseconds ms',
      if (rustIncrementalMatchingPrimaryInputsMilliseconds != null)
        'rustIncrementalMatchingPrimaryInputsMilliseconds: $rustIncrementalMatchingPrimaryInputsMilliseconds ms',
      if (dartIncrementalBuildShouldRunMilliseconds != null)
        'dartIncrementalBuildShouldRunMilliseconds: $dartIncrementalBuildShouldRunMilliseconds ms',
      if (rustIncrementalBuildShouldRunMilliseconds != null)
        'rustIncrementalBuildShouldRunMilliseconds: $rustIncrementalBuildShouldRunMilliseconds ms',
      if (dartIncrementalFreshnessCheckMilliseconds != null)
        'dartIncrementalFreshnessCheckMilliseconds: $dartIncrementalFreshnessCheckMilliseconds ms',
      if (rustIncrementalFreshnessCheckMilliseconds != null)
        'rustIncrementalFreshnessCheckMilliseconds: $rustIncrementalFreshnessCheckMilliseconds ms',
      if (dartIncrementalConfigReloadMilliseconds != null)
        'dartIncrementalConfigReloadMilliseconds: $dartIncrementalConfigReloadMilliseconds ms',
      if (rustIncrementalConfigReloadMilliseconds != null)
        'rustIncrementalConfigReloadMilliseconds: $rustIncrementalConfigReloadMilliseconds ms',
      if (dartIncrementalUntrackedBuildMilliseconds != null)
        'dartIncrementalUntrackedBuildMilliseconds: $dartIncrementalUntrackedBuildMilliseconds ms',
      if (rustIncrementalUntrackedBuildMilliseconds != null)
        'rustIncrementalUntrackedBuildMilliseconds: $rustIncrementalUntrackedBuildMilliseconds ms',
      if (dartIncrementalAssetGraphSerializeProbeMilliseconds != null)
        'dartIncrementalAssetGraphSerializeProbeMilliseconds: $dartIncrementalAssetGraphSerializeProbeMilliseconds ms',
      if (rustIncrementalAssetGraphSerializeProbeMilliseconds != null)
        'rustIncrementalAssetGraphSerializeProbeMilliseconds: $rustIncrementalAssetGraphSerializeProbeMilliseconds ms',
      if (dartIncrementalAssetGraphSerializeProbeBytes != null)
        'dartIncrementalAssetGraphSerializeProbeBytes: $dartIncrementalAssetGraphSerializeProbeBytes bytes',
      if (rustIncrementalAssetGraphSerializeProbeBytes != null)
        'rustIncrementalAssetGraphSerializeProbeBytes: $rustIncrementalAssetGraphSerializeProbeBytes bytes',
      if (dartIncrementalAssetGraphPersistMilliseconds != null)
        'dartIncrementalAssetGraphPersistMilliseconds: $dartIncrementalAssetGraphPersistMilliseconds ms',
      if (rustIncrementalAssetGraphPersistMilliseconds != null)
        'rustIncrementalAssetGraphPersistMilliseconds: $rustIncrementalAssetGraphPersistMilliseconds ms',
      if (dartIncrementalCacheFlushMilliseconds != null)
        'dartIncrementalCacheFlushMilliseconds: $dartIncrementalCacheFlushMilliseconds ms',
      if (rustIncrementalCacheFlushMilliseconds != null)
        'rustIncrementalCacheFlushMilliseconds: $rustIncrementalCacheFlushMilliseconds ms',
      if (dartIncrementalResourceDisposeMilliseconds != null)
        'dartIncrementalResourceDisposeMilliseconds: $dartIncrementalResourceDisposeMilliseconds ms',
      if (rustIncrementalResourceDisposeMilliseconds != null)
        'rustIncrementalResourceDisposeMilliseconds: $rustIncrementalResourceDisposeMilliseconds ms',
      if (dartIncrementalMergedOutputsMilliseconds != null)
        'dartIncrementalMergedOutputsMilliseconds: $dartIncrementalMergedOutputsMilliseconds ms',
      if (rustIncrementalMergedOutputsMilliseconds != null)
        'rustIncrementalMergedOutputsMilliseconds: $rustIncrementalMergedOutputsMilliseconds ms',
      if (dartIncrementalResolverResetMilliseconds != null)
        'dartIncrementalResolverResetMilliseconds: $dartIncrementalResolverResetMilliseconds ms',
      if (rustIncrementalResolverResetMilliseconds != null)
        'rustIncrementalResolverResetMilliseconds: $rustIncrementalResolverResetMilliseconds ms',
      if (dartIncrementalBuildLogFinishMilliseconds != null)
        'dartIncrementalBuildLogFinishMilliseconds: $dartIncrementalBuildLogFinishMilliseconds ms',
      if (rustIncrementalBuildLogFinishMilliseconds != null)
        'rustIncrementalBuildLogFinishMilliseconds: $rustIncrementalBuildLogFinishMilliseconds ms',
      if (rustWatchCollectionSpeedupVsDart != null)
        'rustWatchCollectionSpeedupVsDart: ${rustWatchCollectionSpeedupVsDart!.toStringAsFixed(2)}x',
      if (dartSpeedupVsUpstream != null)
        'dartSpeedupVsUpstream: ${dartSpeedupVsUpstream!.toStringAsFixed(2)}x',
      if (rustSpeedupVsUpstream != null)
        'rustSpeedupVsUpstream: ${rustSpeedupVsUpstream!.toStringAsFixed(2)}x',
      if (rustSpeedupVsDart != null)
        'rustSpeedupVsDart: ${rustSpeedupVsDart!.toStringAsFixed(2)}x',
      if (upstream != null) 'upstreamResult: ${upstream!.result.status}',
      'dartResult: ${dart.result.status}',
      'rustResult: ${rust.result.status}',
    ];
    if (warnings.isNotEmpty) {
      lines.add('warnings:');
      lines.addAll(warnings.map((warning) => '- $warning'));
    }
    if (errors.isNotEmpty) {
      lines.add('errors:');
      lines.addAll(errors.map((error) => '- $error'));
    }
    return lines;
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# fast_build_runner watch benchmark')
      ..writeln()
      ..writeln('- status: `$status`')
      ..writeln('- incremental cycles: `$incrementalCycles`')
      ..writeln('- repeats: `$repeats`')
      ..writeln('- noise files per cycle: `$noiseFilesPerCycle`')
      ..writeln('- continuous scheduling: `$continuousScheduling`')
      ..writeln('- extra fixture models: `$extraFixtureModels`')
      ..writeln('- post-build settle delay: `$settleBuildDelayMs ms`')
      ..writeln('- trust build script freshness: `$trustBuildScriptFreshness`');
    if (upstream != null) {
      buffer.writeln('- upstream: `${upstream!.elapsedMilliseconds} ms`');
    }
    buffer
      ..writeln('- dart: `${dart.elapsedMilliseconds} ms`')
      ..writeln('- rust: `${rust.elapsedMilliseconds} ms`');
    if (upstreamSamples.length > 1) {
      buffer.writeln(
        '- upstream samples: `${upstreamSamples.map((sample) => sample.elapsedMilliseconds).join(', ')}`',
      );
    }
    if (dartSamples.length > 1) {
      buffer.writeln(
        '- dart samples: `${dartSamples.map((sample) => sample.elapsedMilliseconds).join(', ')}`',
      );
    }
    if (rustSamples.length > 1) {
      buffer.writeln(
        '- rust samples: `${rustSamples.map((sample) => sample.elapsedMilliseconds).join(', ')}`',
      );
    }
    if (dart.result.initialBuild != null) {
      buffer.writeln(
        '- dart initial build: `${dart.result.initialBuild!.elapsedMilliseconds} ms`',
      );
    }
    if (rust.result.initialBuild != null) {
      buffer.writeln(
        '- rust initial build: `${rust.result.initialBuild!.elapsedMilliseconds} ms`',
      );
    }
    if (upstream?.result.incrementalBuild != null) {
      buffer.writeln(
        '- upstream incremental build: `${upstream!.result.incrementalBuild!.elapsedMilliseconds} ms`',
      );
    }
    if (dart.result.incrementalBuild != null) {
      buffer.writeln(
        '- dart incremental build: `${dart.result.incrementalBuild!.elapsedMilliseconds} ms`',
      );
    }
    if (rust.result.incrementalBuild != null) {
      buffer.writeln(
        '- rust incremental build: `${rust.result.incrementalBuild!.elapsedMilliseconds} ms`',
      );
    }
    if (upstreamTotalIncrementalBuildMilliseconds != null) {
      buffer.writeln(
        '- upstream total incremental build: `$upstreamTotalIncrementalBuildMilliseconds ms`',
      );
    }
    if (dartTotalIncrementalBuildMilliseconds != null) {
      buffer.writeln(
        '- dart total incremental build: `$dartTotalIncrementalBuildMilliseconds ms`',
      );
    }
    if (rustTotalIncrementalBuildMilliseconds != null) {
      buffer.writeln(
        '- rust total incremental build: `$rustTotalIncrementalBuildMilliseconds ms`',
      );
    }
    if (dart.result.watchCollectionMilliseconds.isNotEmpty) {
      buffer.writeln(
        '- dart watch collection: `${dart.result.watchCollectionMilliseconds.join(', ')} ms`',
      );
    }
    if (rust.result.watchCollectionMilliseconds.isNotEmpty) {
      buffer.writeln(
        '- rust watch collection: `${rust.result.watchCollectionMilliseconds.join(', ')} ms`',
      );
    }
    if (dartTotalWatchCollectionMilliseconds != null) {
      buffer.writeln(
        '- dart total watch collection: `$dartTotalWatchCollectionMilliseconds ms`',
      );
    }
    if (rustTotalWatchCollectionMilliseconds != null) {
      buffer.writeln(
        '- rust total watch collection: `$rustTotalWatchCollectionMilliseconds ms`',
      );
    }
    if (rust.result.rustDaemonStartupMilliseconds != null) {
      buffer.writeln(
        '- rust daemon startup: `${rust.result.rustDaemonStartupMilliseconds} ms`',
      );
    }
    if (rustSpeedupVsDart != null) {
      buffer.writeln(
        '- rust speedup vs dart: `${rustSpeedupVsDart!.toStringAsFixed(2)}x`',
      );
    }
    if (dartSpeedupVsUpstream != null) {
      buffer.writeln(
        '- dart speedup vs upstream: `${dartSpeedupVsUpstream!.toStringAsFixed(2)}x`',
      );
    }
    if (rustSpeedupVsUpstream != null) {
      buffer.writeln(
        '- rust speedup vs upstream: `${rustSpeedupVsUpstream!.toStringAsFixed(2)}x`',
      );
    }
    if (rustInitialBuildSpeedupVsUpstream != null) {
      buffer.writeln(
        '- rust initial build speedup vs upstream: `${rustInitialBuildSpeedupVsUpstream!.toStringAsFixed(2)}x`',
      );
    }
    if (rustInitialBuildSpeedupVsDart != null) {
      buffer.writeln(
        '- rust initial build speedup vs dart: `${rustInitialBuildSpeedupVsDart!.toStringAsFixed(2)}x`',
      );
    }
    if (rustIncrementalBuildSpeedupVsUpstream != null) {
      buffer.writeln(
        '- rust incremental build speedup vs upstream: `${rustIncrementalBuildSpeedupVsUpstream!.toStringAsFixed(2)}x`',
      );
    }
    if (rustIncrementalBuildSpeedupVsDart != null) {
      buffer.writeln(
        '- rust incremental build speedup vs dart: `${rustIncrementalBuildSpeedupVsDart!.toStringAsFixed(2)}x`',
      );
    }
    if (rustTotalIncrementalBuildSpeedupVsUpstream != null) {
      buffer.writeln(
        '- rust total incremental build speedup vs upstream: `${rustTotalIncrementalBuildSpeedupVsUpstream!.toStringAsFixed(2)}x`',
      );
    }
    if (rustTotalIncrementalBuildSpeedupVsDart != null) {
      buffer.writeln(
        '- rust total incremental build speedup vs dart: `${rustTotalIncrementalBuildSpeedupVsDart!.toStringAsFixed(2)}x`',
      );
    }
    if (rustWatchCollectionSpeedupVsDart != null) {
      buffer.writeln(
        '- rust watch collection speedup vs dart: `${rustWatchCollectionSpeedupVsDart!.toStringAsFixed(2)}x`',
      );
    }
    if (upstream != null) {
      buffer.writeln('- upstream result: `${upstream!.result.status}`');
    }
    buffer
      ..writeln('- dart result: `${dart.result.status}`')
      ..writeln('- rust result: `${rust.result.status}`');

    if (warnings.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Warnings');
      for (final warning in warnings) {
        buffer.writeln('- $warning');
      }
    }
    if (errors.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Errors');
      for (final error in errors) {
        buffer.writeln('- $error');
      }
    }
    return buffer.toString().trimRight();
  }
}

int _minSampleCount(
  List<FastWatchBenchmarkEngineResult> upstreamSamples,
  List<FastWatchBenchmarkEngineResult> dartSamples,
  List<FastWatchBenchmarkEngineResult> rustSamples,
) {
  final counts = <int>[dartSamples.length, rustSamples.length];
  if (upstreamSamples.isNotEmpty) {
    counts.add(upstreamSamples.length);
  }
  return counts.reduce((a, b) => a < b ? a : b);
}

int? _totalIncrementalBuildMilliseconds(List<FastBuildStepResult>? builds) {
  if (builds == null || builds.isEmpty) {
    return null;
  }
  return builds.map((step) => step.elapsedMilliseconds).reduce((a, b) => a + b);
}

int? _totalCollectionMilliseconds(List<int> timings) {
  if (timings.isEmpty) {
    return null;
  }
  return timings.reduce((a, b) => a + b);
}

FastWatchBenchmarkEngineResult _medianSample(
  List<FastWatchBenchmarkEngineResult> samples,
) {
  final sorted = [...samples]
    ..sort((a, b) => a.elapsedMilliseconds.compareTo(b.elapsedMilliseconds));
  return sorted[(sorted.length - 1) ~/ 2];
}
