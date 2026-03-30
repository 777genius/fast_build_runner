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
  double? get rustInitialBuildSpeedupVsDart {
    final dartInitial = dart.result.initialBuild?.elapsedMilliseconds;
    final rustInitial = rust.result.initialBuild?.elapsedMilliseconds;
    if (dartInitial == null || rustInitial == null || rustInitial == 0) {
      return null;
    }
    return dartInitial / rustInitial;
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

  Map<String, Object?> toJson() => {
    'status': status,
    'incrementalCycles': incrementalCycles,
    'dart': dart.toJson(),
    'rust': rust.toJson(),
    'rustSpeedupVsDart': rustSpeedupVsDart,
    'rustInitialBuildSpeedupVsDart': rustInitialBuildSpeedupVsDart,
    'rustIncrementalBuildSpeedupVsDart': rustIncrementalBuildSpeedupVsDart,
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
      if (dart.result.initialBuild != null)
        'dartInitialBuild: ${dart.result.initialBuild!.elapsedMilliseconds} ms',
      if (rust.result.initialBuild != null)
        'rustInitialBuild: ${rust.result.initialBuild!.elapsedMilliseconds} ms',
      if (dart.result.incrementalBuild != null)
        'dartIncrementalBuild: ${dart.result.incrementalBuild!.elapsedMilliseconds} ms',
      if (rust.result.incrementalBuild != null)
        'rustIncrementalBuild: ${rust.result.incrementalBuild!.elapsedMilliseconds} ms',
      if (rustInitialBuildSpeedupVsDart != null)
        'rustInitialBuildSpeedupVsDart: ${rustInitialBuildSpeedupVsDart!.toStringAsFixed(2)}x',
      if (rustIncrementalBuildSpeedupVsDart != null)
        'rustIncrementalBuildSpeedupVsDart: ${rustIncrementalBuildSpeedupVsDart!.toStringAsFixed(2)}x',
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
    if (rustSpeedupVsDart != null) {
      buffer.writeln(
        '- rust speedup vs dart: `${rustSpeedupVsDart!.toStringAsFixed(2)}x`',
      );
    }
    if (rustInitialBuildSpeedupVsDart != null) {
      buffer.writeln(
        '- rust initial build speedup vs dart: `${rustInitialBuildSpeedupVsDart!.toStringAsFixed(2)}x`',
      );
    }
    if (rustIncrementalBuildSpeedupVsDart != null) {
      buffer.writeln(
        '- rust incremental build speedup vs dart: `${rustIncrementalBuildSpeedupVsDart!.toStringAsFixed(2)}x`',
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
