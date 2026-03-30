import 'dart:io';

import 'package:fast_build_runner_internal/fast_build_runner_internal.dart';
import 'package:test/test.dart';

void main() {
  test(
    'watch benchmark compares dart and rust source engines',
    () async {
      final repoRoot = Directory.current.path;
      final result = await FastWatchBenchmarkRunner().run(
        FastWatchBenchmarkRequest(
          repoRoot: repoRoot,
          fixtureTemplatePath: '$repoRoot/fixtures/json_serializable_fixture',
          workDirectoryPath: '$repoRoot/.dart_tool/test_watch_benchmark',
          keepRunDirectory: false,
        ),
      );

      expect(result.status, 'success');
      expect(result.incrementalCycles, 1);
      expect(result.dart.sourceEngine, 'dart');
      expect(result.rust.sourceEngine, 'rust');
      expect(result.dart.result.isSuccess, isTrue);
      expect(result.rust.result.isSuccess, isTrue);
      expect(result.dart.elapsedMilliseconds, greaterThan(0));
      expect(result.rust.elapsedMilliseconds, greaterThan(0));
      expect(result.rustSpeedupVsDart, isNotNull);
      expect(result.warnings, isNotEmpty);
      expect(result.errors, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('watch benchmark can render summary and markdown output', () {
    final result = FastWatchBenchmarkResult(
      status: 'success',
      incrementalCycles: 2,
      dart: FastWatchBenchmarkEngineResult(
        sourceEngine: 'dart',
        elapsedMilliseconds: 1200,
        result: const FastWatchAlphaResult(
          status: 'success',
          sourceEngine: 'dart',
          upstreamCommit: 'commit',
          generatedEntrypointPath: 'entrypoint',
          runDirectory: 'run-dart',
          warnings: [],
          errors: [],
          observedEvents: [],
          mergedUpdates: [],
          observedEventBatches: [],
          mergedUpdateBatches: [],
          initialBuild: null,
          incrementalBuild: null,
          incrementalBuilds: [],
        ),
      ),
      rust: FastWatchBenchmarkEngineResult(
        sourceEngine: 'rust',
        elapsedMilliseconds: 800,
        result: const FastWatchAlphaResult(
          status: 'success',
          sourceEngine: 'rust',
          upstreamCommit: 'commit',
          generatedEntrypointPath: 'entrypoint',
          runDirectory: 'run-rust',
          warnings: [],
          errors: [],
          observedEvents: [],
          mergedUpdates: [],
          observedEventBatches: [],
          mergedUpdateBatches: [],
          initialBuild: null,
          incrementalBuild: null,
          incrementalBuilds: [],
        ),
      ),
      rustSpeedupVsDart: 1.5,
      warnings: const ['speedup is illustrative'],
      errors: const [],
    );

    final summary = result.toSummaryLines().join('\n');
    final markdown = result.toMarkdown();

    expect(summary, contains('dart: 1200 ms'));
    expect(summary, contains('rustSpeedupVsDart: 1.50x'));
    expect(markdown, contains('# fast_build_runner watch benchmark'));
    expect(markdown, contains('- rust speedup vs dart: `1.50x`'));
  });
}
