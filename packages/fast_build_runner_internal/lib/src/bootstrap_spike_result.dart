class FastBuildStepResult {
  final String name;
  final int elapsedMilliseconds;
  final String status;
  final String? failureType;
  final List<String> outputs;
  final List<String> errors;
  final bool generatedFileExists;
  final bool generatedFileHasMutation;

  const FastBuildStepResult({
    required this.name,
    required this.elapsedMilliseconds,
    required this.status,
    required this.failureType,
    required this.outputs,
    required this.errors,
    required this.generatedFileExists,
    required this.generatedFileHasMutation,
  });

  Map<String, Object?> toJson() => {
    'name': name,
    'elapsedMilliseconds': elapsedMilliseconds,
    'status': status,
    'failureType': failureType,
    'outputs': outputs,
    'errors': errors,
    'generatedFileExists': generatedFileExists,
    'generatedFileHasMutation': generatedFileHasMutation,
  };

  static FastBuildStepResult fromJson(Map<String, Object?> json) =>
      FastBuildStepResult(
        name: json['name']! as String,
        elapsedMilliseconds: json['elapsedMilliseconds']! as int,
        status: json['status']! as String,
        failureType: json['failureType'] as String?,
        outputs: List<String>.from(json['outputs']! as List),
        errors: List<String>.from(json['errors']! as List),
        generatedFileExists: json['generatedFileExists']! as bool,
        generatedFileHasMutation: json['generatedFileHasMutation']! as bool,
      );
}

class FastBootstrapSpikeResult {
  final String status;
  final String upstreamCommit;
  final String generatedEntrypointPath;
  final String runDirectory;
  final List<String> warnings;
  final List<String> errors;
  final FastBuildStepResult? initialBuild;
  final FastBuildStepResult? incrementalBuild;

  const FastBootstrapSpikeResult({
    required this.status,
    required this.upstreamCommit,
    required this.generatedEntrypointPath,
    required this.runDirectory,
    required this.warnings,
    required this.errors,
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
    'initialBuild': initialBuild?.toJson(),
    'incrementalBuild': incrementalBuild?.toJson(),
  };

  static FastBootstrapSpikeResult fromJson(Map<String, Object?> json) =>
      FastBootstrapSpikeResult(
        status: json['status']! as String,
        upstreamCommit: json['upstreamCommit']! as String,
        generatedEntrypointPath: json['generatedEntrypointPath']! as String,
        runDirectory: json['runDirectory']! as String,
        warnings: List<String>.from(json['warnings']! as List),
        errors: List<String>.from(json['errors']! as List),
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
      );
}
