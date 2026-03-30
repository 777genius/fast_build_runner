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

  List<String> toSummaryLines() {
    final lines = <String>[
      'fast_build_runner watch benchmark',
      'status: $status',
      'incrementalCycles: $incrementalCycles',
      'dart: ${dart.elapsedMilliseconds} ms',
      'rust: ${rust.elapsedMilliseconds} ms',
      if (rustSpeedupVsDart != null)
        'rustSpeedupVsDart: ${rustSpeedupVsDart!.toStringAsFixed(2)}x',
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
      ..writeln('- dart: `${dart.elapsedMilliseconds} ms`')
      ..writeln('- rust: `${rust.elapsedMilliseconds} ms`');
    if (rustSpeedupVsDart != null) {
      buffer.writeln(
        '- rust speedup vs dart: `${rustSpeedupVsDart!.toStringAsFixed(2)}x`',
      );
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
