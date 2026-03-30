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

    return FastWatchBenchmarkResult.fromRuns(
      incrementalCycles: request.incrementalCycles,
      dart: dartRun,
      rust: rustRun,
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
