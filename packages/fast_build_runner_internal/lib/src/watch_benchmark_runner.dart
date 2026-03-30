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
    final dartRuns = await _runCases(
      sourceEngine: 'dart',
      workDirectoryPath: p.join(request.workDirectoryPath, 'dart'),
      request: request,
    );
    final rustRuns = await _runCases(
      sourceEngine: 'rust',
      workDirectoryPath: p.join(request.workDirectoryPath, 'rust'),
      request: request,
    );

    return FastWatchBenchmarkResult.fromRuns(
      incrementalCycles: request.incrementalCycles,
      noiseFilesPerCycle: request.noiseFilesPerCycle,
      continuousScheduling: request.continuousScheduling,
      extraFixtureModels: request.extraFixtureModels,
      dartSamples: dartRuns,
      rustSamples: rustRuns,
    );
  }

  Future<List<FastWatchBenchmarkEngineResult>> _runCases({
    required String sourceEngine,
    required String workDirectoryPath,
    required FastWatchBenchmarkRequest request,
  }) async {
    final samples = <FastWatchBenchmarkEngineResult>[];
    for (var i = 0; i < request.repeats; i++) {
      final stopwatch = Stopwatch()..start();
      final result = await FastWatchAlphaRunner().run(
        FastWatchAlphaRequest(
          repoRoot: request.repoRoot,
          fixtureTemplatePath: request.fixtureTemplatePath,
          workDirectoryPath: p.join(workDirectoryPath, 'run-${i + 1}'),
          keepRunDirectory: request.keepRunDirectory,
          sourceEngine: sourceEngine,
          incrementalCycles: request.incrementalCycles,
          noiseFilesPerCycle: request.noiseFilesPerCycle,
          continuousScheduling: request.continuousScheduling,
          extraFixtureModels: request.extraFixtureModels,
        ),
      );
      stopwatch.stop();
      samples.add(
        FastWatchBenchmarkEngineResult(
          sourceEngine: sourceEngine,
          elapsedMilliseconds: stopwatch.elapsedMilliseconds,
          result: result,
        ),
      );
    }
    return samples;
  }
}
