import 'bootstrap_spike_result.dart';

class FastWatchAlphaResult {
  final String status;
  final String upstreamCommit;
  final String generatedEntrypointPath;
  final String runDirectory;
  final List<String> warnings;
  final List<String> errors;
  final List<String> observedEvents;
  final FastBuildStepResult? initialBuild;
  final FastBuildStepResult? incrementalBuild;

  const FastWatchAlphaResult({
    required this.status,
    required this.upstreamCommit,
    required this.generatedEntrypointPath,
    required this.runDirectory,
    required this.warnings,
    required this.errors,
    required this.observedEvents,
    required this.initialBuild,
    required this.incrementalBuild,
  });

  bool get isSuccess => status == 'success';
  int get exitCode => isSuccess ? 0 : 1;

  Map<String, Object?> toJson() => {
    'status': status,
    'upstreamCommit': upstreamCommit,
    'generatedEntrypointPath': generatedEntrypointPath,
    'runDirectory': runDirectory,
    'warnings': warnings,
    'errors': errors,
    'observedEvents': observedEvents,
    'initialBuild': initialBuild?.toJson(),
    'incrementalBuild': incrementalBuild?.toJson(),
  };

  static FastWatchAlphaResult fromJson(Map<String, Object?> json) =>
      FastWatchAlphaResult(
        status: json['status']! as String,
        upstreamCommit: json['upstreamCommit']! as String,
        generatedEntrypointPath: json['generatedEntrypointPath']! as String,
        runDirectory: json['runDirectory']! as String,
        warnings: List<String>.from(json['warnings']! as List),
        errors: List<String>.from(json['errors']! as List),
        observedEvents: List<String>.from(json['observedEvents']! as List),
        initialBuild:
            json['initialBuild'] == null
                ? null
                : FastBuildStepResult.fromJson(
                  Map<String, Object?>.from(json['initialBuild']! as Map),
                ),
        incrementalBuild:
            json['incrementalBuild'] == null
                ? null
                : FastBuildStepResult.fromJson(
                  Map<String, Object?>.from(json['incrementalBuild']! as Map),
                ),
      );
}
