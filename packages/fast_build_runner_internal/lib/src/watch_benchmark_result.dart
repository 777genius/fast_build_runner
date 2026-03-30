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
  final FastWatchBenchmarkEngineResult dart;
  final FastWatchBenchmarkEngineResult rust;
  final List<FastWatchBenchmarkEngineResult> dartSamples;
  final List<FastWatchBenchmarkEngineResult> rustSamples;
  final double? rustSpeedupVsDart;
  final List<String> warnings;
  final List<String> errors;

  const FastWatchBenchmarkResult({
    required this.status,
    required this.incrementalCycles,
    required this.repeats,
    required this.dart,
    required this.rust,
    required this.dartSamples,
    required this.rustSamples,
    required this.rustSpeedupVsDart,
    required this.warnings,
    required this.errors,
  });

  factory FastWatchBenchmarkResult.fromRuns({
    required int incrementalCycles,
    required List<FastWatchBenchmarkEngineResult> dartSamples,
    required List<FastWatchBenchmarkEngineResult> rustSamples,
  }) {
    if (dartSamples.isEmpty || rustSamples.isEmpty) {
      throw StateError('Benchmark samples must not be empty.');
    }
    final dart = _medianSample(dartSamples);
    final rust = _medianSample(rustSamples);
    final rustSpeedupVsDart = rust.elapsedMilliseconds > 0
        ? dart.elapsedMilliseconds / rust.elapsedMilliseconds
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
      if (rustIncrementalBuildSpeedupVsDart != null &&
          rustSpeedupVsDart != null &&
          rustIncrementalBuildSpeedupVsDart > rustSpeedupVsDart + 0.1)
        'Incremental build speedup is stronger than total wall-clock speedup, which suggests initial build cost still dominates this fixture.',
    ];
    final errors = <String>[
      if (!dart.result.isSuccess)
        'Dart benchmark run failed: ${dart.result.errors.join(' | ')}',
      if (!rust.result.isSuccess)
        'Rust benchmark run failed: ${rust.result.errors.join(' | ')}',
    ];

    return FastWatchBenchmarkResult(
      status: errors.isEmpty ? 'success' : 'failure',
      incrementalCycles: incrementalCycles,
      repeats: dartSamples.length < rustSamples.length
          ? dartSamples.length
          : rustSamples.length,
      dart: dart,
      rust: rust,
      dartSamples: dartSamples,
      rustSamples: rustSamples,
      rustSpeedupVsDart: rustSpeedupVsDart,
      warnings: warnings,
      errors: errors,
    );
  }

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

  Map<String, Object?> toJson() => {
    'status': status,
    'incrementalCycles': incrementalCycles,
    'repeats': repeats,
    'dart': dart.toJson(),
    'rust': rust.toJson(),
    'dartSamples': dartSamples.map((sample) => sample.toJson()).toList(),
    'rustSamples': rustSamples.map((sample) => sample.toJson()).toList(),
    'rustSpeedupVsDart': rustSpeedupVsDart,
    'rustInitialBuildSpeedupVsDart': rustInitialBuildSpeedupVsDart,
    'rustIncrementalBuildSpeedupVsDart': rustIncrementalBuildSpeedupVsDart,
    'rustWatchCollectionSpeedupVsDart': rustWatchCollectionSpeedupVsDart,
    'warnings': warnings,
    'errors': errors,
  };

  List<String> toSummaryLines() {
    final lines = <String>[
      'fast_build_runner watch benchmark',
      'status: $status',
      'incrementalCycles: $incrementalCycles',
      'repeats: $repeats',
      'dart: ${dart.elapsedMilliseconds} ms',
      'rust: ${rust.elapsedMilliseconds} ms',
      if (dartSamples.length > 1)
        'dartSamples: ${dartSamples.map((sample) => sample.elapsedMilliseconds).join(', ')}',
      if (rustSamples.length > 1)
        'rustSamples: ${rustSamples.map((sample) => sample.elapsedMilliseconds).join(', ')}',
      if (dart.result.initialBuild != null)
        'dartInitialBuild: ${dart.result.initialBuild!.elapsedMilliseconds} ms',
      if (rust.result.initialBuild != null)
        'rustInitialBuild: ${rust.result.initialBuild!.elapsedMilliseconds} ms',
      if (dart.result.incrementalBuild != null)
        'dartIncrementalBuild: ${dart.result.incrementalBuild!.elapsedMilliseconds} ms',
      if (rust.result.incrementalBuild != null)
        'rustIncrementalBuild: ${rust.result.incrementalBuild!.elapsedMilliseconds} ms',
      if (dart.result.watchCollectionMilliseconds.isNotEmpty)
        'dartWatchCollection: ${dart.result.watchCollectionMilliseconds.join(', ')} ms',
      if (rust.result.watchCollectionMilliseconds.isNotEmpty)
        'rustWatchCollection: ${rust.result.watchCollectionMilliseconds.join(', ')} ms',
      if (rust.result.rustDaemonStartupMilliseconds != null)
        'rustDaemonStartup: ${rust.result.rustDaemonStartupMilliseconds} ms',
      if (rustInitialBuildSpeedupVsDart != null)
        'rustInitialBuildSpeedupVsDart: ${rustInitialBuildSpeedupVsDart!.toStringAsFixed(2)}x',
      if (rustIncrementalBuildSpeedupVsDart != null)
        'rustIncrementalBuildSpeedupVsDart: ${rustIncrementalBuildSpeedupVsDart!.toStringAsFixed(2)}x',
      if (rustWatchCollectionSpeedupVsDart != null)
        'rustWatchCollectionSpeedupVsDart: ${rustWatchCollectionSpeedupVsDart!.toStringAsFixed(2)}x',
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
      ..writeln('- repeats: `$repeats`')
      ..writeln('- dart: `${dart.elapsedMilliseconds} ms`')
      ..writeln('- rust: `${rust.elapsedMilliseconds} ms`');
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
    if (rustWatchCollectionSpeedupVsDart != null) {
      buffer.writeln(
        '- rust watch collection speedup vs dart: `${rustWatchCollectionSpeedupVsDart!.toStringAsFixed(2)}x`',
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

FastWatchBenchmarkEngineResult _medianSample(
  List<FastWatchBenchmarkEngineResult> samples,
) {
  final sorted = [...samples]
    ..sort((a, b) => a.elapsedMilliseconds.compareTo(b.elapsedMilliseconds));
  return sorted[(sorted.length - 1) ~/ 2];
}
