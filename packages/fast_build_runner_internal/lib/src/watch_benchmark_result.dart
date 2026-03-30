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
  final FastWatchBenchmarkEngineResult dart;
  final FastWatchBenchmarkEngineResult rust;
  final double? rustSpeedupVsDart;
  final List<String> warnings;
  final List<String> errors;

  const FastWatchBenchmarkResult({
    required this.status,
    required this.incrementalCycles,
    required this.dart,
    required this.rust,
    required this.rustSpeedupVsDart,
    required this.warnings,
    required this.errors,
  });

  bool get isSuccess => status == 'success';
  int get exitCode => isSuccess ? 0 : 1;

  Map<String, Object?> toJson() => {
    'status': status,
    'incrementalCycles': incrementalCycles,
    'dart': dart.toJson(),
    'rust': rust.toJson(),
    'rustSpeedupVsDart': rustSpeedupVsDart,
    'warnings': warnings,
    'errors': errors,
  };
}
