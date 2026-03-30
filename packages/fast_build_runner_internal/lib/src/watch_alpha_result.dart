import 'bootstrap_spike_result.dart';

class FastWatchAlphaResult {
  final String status;
  final String sourceEngine;
  final String upstreamCommit;
  final String generatedEntrypointPath;
  final String runDirectory;
  final List<String> warnings;
  final List<String> errors;
  final List<String> observedEvents;
  final List<String> mergedUpdates;
  final List<List<String>> observedEventBatches;
  final List<List<String>> mergedUpdateBatches;
  final int? rustDaemonStartupMilliseconds;
  final List<int> watchCollectionMilliseconds;
  final FastBuildStepResult? initialBuild;
  final FastBuildStepResult? incrementalBuild;
  final List<FastBuildStepResult> incrementalBuilds;

  const FastWatchAlphaResult({
    required this.status,
    required this.sourceEngine,
    required this.upstreamCommit,
    required this.generatedEntrypointPath,
    required this.runDirectory,
    required this.warnings,
    required this.errors,
    required this.observedEvents,
    required this.mergedUpdates,
    required this.observedEventBatches,
    required this.mergedUpdateBatches,
    this.rustDaemonStartupMilliseconds,
    this.watchCollectionMilliseconds = const [],
    required this.initialBuild,
    required this.incrementalBuild,
    required this.incrementalBuilds,
  });

  bool get isSuccess => status == 'success';
  int get exitCode => isSuccess ? 0 : 1;

  Map<String, Object?> toJson() => {
    'status': status,
    'sourceEngine': sourceEngine,
    'upstreamCommit': upstreamCommit,
    'generatedEntrypointPath': generatedEntrypointPath,
    'runDirectory': runDirectory,
    'warnings': warnings,
    'errors': errors,
    'observedEvents': observedEvents,
    'mergedUpdates': mergedUpdates,
    'observedEventBatches': observedEventBatches,
    'mergedUpdateBatches': mergedUpdateBatches,
    'rustDaemonStartupMilliseconds': rustDaemonStartupMilliseconds,
    'watchCollectionMilliseconds': watchCollectionMilliseconds,
    'initialBuild': initialBuild?.toJson(),
    'incrementalBuild': incrementalBuild?.toJson(),
    'incrementalBuilds': incrementalBuilds
        .map((step) => step.toJson())
        .toList(),
  };

  static FastWatchAlphaResult fromJson(Map<String, Object?> json) =>
      FastWatchAlphaResult(
        status: json['status']! as String,
        sourceEngine: json['sourceEngine']! as String,
        upstreamCommit: json['upstreamCommit']! as String,
        generatedEntrypointPath: json['generatedEntrypointPath']! as String,
        runDirectory: json['runDirectory']! as String,
        warnings: List<String>.from(json['warnings']! as List),
        errors: List<String>.from(json['errors']! as List),
        observedEvents: List<String>.from(json['observedEvents']! as List),
        mergedUpdates: List<String>.from(json['mergedUpdates']! as List),
        observedEventBatches:
            (json['observedEventBatches'] as List? ?? const [])
                .map((batch) => List<String>.from(batch as List))
                .toList(),
        mergedUpdateBatches: (json['mergedUpdateBatches'] as List? ?? const [])
            .map((batch) => List<String>.from(batch as List))
            .toList(),
        rustDaemonStartupMilliseconds:
            json['rustDaemonStartupMilliseconds'] as int?,
        watchCollectionMilliseconds: List<int>.from(
          json['watchCollectionMilliseconds'] as List? ?? const [],
        ),
        initialBuild: json['initialBuild'] == null
            ? null
            : FastBuildStepResult.fromJson(
                Map<String, Object?>.from(json['initialBuild']! as Map),
              ),
        incrementalBuild: json['incrementalBuild'] == null
            ? null
            : FastBuildStepResult.fromJson(
                Map<String, Object?>.from(json['incrementalBuild']! as Map),
              ),
        incrementalBuilds: (json['incrementalBuilds'] as List? ?? const [])
            .map(
              (step) => FastBuildStepResult.fromJson(
                Map<String, Object?>.from(step as Map),
              ),
            )
            .toList(),
      );
}
