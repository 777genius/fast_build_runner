import 'dart:async';

import 'package:path/path.dart' as p;

import 'watch_alpha_request.dart';
import 'watch_alpha_runner.dart';
import 'watch_benchmark_request.dart';
import 'watch_benchmark_result.dart';

class FastWatchBenchmarkRunner {
  Future<FastWatchBenchmarkResult> run(
    FastWatchBenchmarkRequest request,
  ) async {
    final dartRun = await _runCase(
      sourceEngine: 'dart',
      workDirectoryPath: p.join(request.workDirectoryPath, 'dart'),
      request: request,
    );
    final rustRun = await _runCase(
      sourceEngine: 'rust',
      workDirectoryPath: p.join(request.workDirectoryPath, 'rust'),
      request: request,
    );

    final speedup = rustRun.elapsedMilliseconds > 0
        ? dartRun.elapsedMilliseconds / rustRun.elapsedMilliseconds
        : null;
    final warnings = <String>[
      if (speedup != null)
        'Rust source engine speedup vs dart source engine: ${speedup.toStringAsFixed(2)}x',
    ];
    final errors = <String>[
      if (!dartRun.result.isSuccess)
        'Dart benchmark run failed: ${dartRun.result.errors.join(' | ')}',
      if (!rustRun.result.isSuccess)
        'Rust benchmark run failed: ${rustRun.result.errors.join(' | ')}',
    ];

    return FastWatchBenchmarkResult(
      status: errors.isEmpty ? 'success' : 'failure',
      incrementalCycles: request.incrementalCycles,
      dart: dartRun,
      rust: rustRun,
      rustSpeedupVsDart: speedup,
      warnings: warnings,
      errors: errors,
    );
  }

  Future<FastWatchBenchmarkEngineResult> _runCase({
    required String sourceEngine,
    required String workDirectoryPath,
    required FastWatchBenchmarkRequest request,
  }) async {
    final stopwatch = Stopwatch()..start();
    final result = await FastWatchAlphaRunner().run(
      FastWatchAlphaRequest(
        repoRoot: request.repoRoot,
        fixtureTemplatePath: request.fixtureTemplatePath,
        workDirectoryPath: workDirectoryPath,
        keepRunDirectory: request.keepRunDirectory,
        sourceEngine: sourceEngine,
        incrementalCycles: request.incrementalCycles,
      ),
    );
    stopwatch.stop();
    return FastWatchBenchmarkEngineResult(
      sourceEngine: sourceEngine,
      elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      result: result,
    );
  }
}
