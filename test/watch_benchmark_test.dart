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
          noiseFilesPerCycle: 2,
        ),
      );

      expect(result.status, 'success');
      expect(result.incrementalCycles, 1);
      expect(result.repeats, 1);
      expect(result.noiseFilesPerCycle, 2);
      expect(result.dart.sourceEngine, 'dart');
      expect(result.rust.sourceEngine, 'rust');
      expect(result.dartSamples, hasLength(1));
      expect(result.rustSamples, hasLength(1));
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
      repeats: 2,
      noiseFilesPerCycle: 3,
      continuousScheduling: true,
      extraFixtureModels: 12,
      settleBuildDelayMs: 90,
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
          watchCollectionMilliseconds: [410, 420],
          initialBuild: FastBuildStepResult(
            name: 'initial',
            elapsedMilliseconds: 900,
            status: 'success',
            failureType: null,
            outputs: [],
            errors: [],
            generatedFileExists: true,
            generatedFileHasMutation: false,
          ),
          incrementalBuild: FastBuildStepResult(
            name: 'incremental-1',
            elapsedMilliseconds: 120,
            status: 'success',
            failureType: null,
            outputs: [],
            errors: [],
            generatedFileExists: true,
            generatedFileHasMutation: true,
          ),
          incrementalBuilds: [
            FastBuildStepResult(
              name: 'incremental-1',
              elapsedMilliseconds: 120,
              status: 'success',
              failureType: null,
              outputs: [],
              errors: [],
              generatedFileExists: true,
              generatedFileHasMutation: true,
            ),
          ],
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
          rustDaemonStartupMilliseconds: 180,
          watchCollectionMilliseconds: [260, 280],
          initialBuild: FastBuildStepResult(
            name: 'initial',
            elapsedMilliseconds: 850,
            status: 'success',
            failureType: null,
            outputs: [],
            errors: [],
            generatedFileExists: true,
            generatedFileHasMutation: false,
          ),
          incrementalBuild: FastBuildStepResult(
            name: 'incremental-1',
            elapsedMilliseconds: 80,
            status: 'success',
            failureType: null,
            outputs: [],
            errors: [],
            generatedFileExists: true,
            generatedFileHasMutation: true,
          ),
          incrementalBuilds: [
            FastBuildStepResult(
              name: 'incremental-1',
              elapsedMilliseconds: 80,
              status: 'success',
              failureType: null,
              outputs: [],
              errors: [],
              generatedFileExists: true,
              generatedFileHasMutation: true,
            ),
          ],
        ),
      ),
      dartSamples: const [
        FastWatchBenchmarkEngineResult(
          sourceEngine: 'dart',
          elapsedMilliseconds: 1200,
          result: FastWatchAlphaResult(
            status: 'success',
            sourceEngine: 'dart',
            upstreamCommit: 'commit',
            generatedEntrypointPath: 'entrypoint',
            runDirectory: 'sample-dart-1',
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
        FastWatchBenchmarkEngineResult(
          sourceEngine: 'dart',
          elapsedMilliseconds: 1400,
          result: FastWatchAlphaResult(
            status: 'success',
            sourceEngine: 'dart',
            upstreamCommit: 'commit',
            generatedEntrypointPath: 'entrypoint',
            runDirectory: 'sample-dart-2',
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
      ],
      rustSamples: const [
        FastWatchBenchmarkEngineResult(
          sourceEngine: 'rust',
          elapsedMilliseconds: 800,
          result: FastWatchAlphaResult(
            status: 'success',
            sourceEngine: 'rust',
            upstreamCommit: 'commit',
            generatedEntrypointPath: 'entrypoint',
            runDirectory: 'sample-rust-1',
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
        FastWatchBenchmarkEngineResult(
          sourceEngine: 'rust',
          elapsedMilliseconds: 900,
          result: FastWatchAlphaResult(
            status: 'success',
            sourceEngine: 'rust',
            upstreamCommit: 'commit',
            generatedEntrypointPath: 'entrypoint',
            runDirectory: 'sample-rust-2',
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
      ],
      rustSpeedupVsDart: 1.5,
      warnings: const ['speedup is illustrative'],
      errors: const [],
    );

    final summary = result.toSummaryLines().join('\n');
    final markdown = result.toMarkdown();

    expect(summary, contains('dart: 1200 ms'));
    expect(summary, contains('repeats: 2'));
    expect(summary, contains('noiseFilesPerCycle: 3'));
    expect(summary, contains('continuousScheduling: true'));
    expect(summary, contains('extraFixtureModels: 12'));
    expect(summary, contains('settleBuildDelayMs: 90'));
    expect(summary, contains('dartSamples: 1200, 1400'));
    expect(summary, contains('rustSamples: 800, 900'));
    expect(summary, contains('dartIncrementalBuild: 120 ms'));
    expect(summary, contains('rustIncrementalBuild: 80 ms'));
    expect(summary, contains('dartTotalIncrementalBuild: 120 ms'));
    expect(summary, contains('rustTotalIncrementalBuild: 80 ms'));
    expect(summary, contains('dartWatchCollection: 410, 420 ms'));
    expect(summary, contains('rustWatchCollection: 260, 280 ms'));
    expect(summary, contains('dartTotalWatchCollection: 830 ms'));
    expect(summary, contains('rustTotalWatchCollection: 540 ms'));
    expect(summary, contains('rustDaemonStartup: 180 ms'));
    expect(summary, contains('rustInitialBuildSpeedupVsDart: 1.06x'));
    expect(summary, contains('rustIncrementalBuildSpeedupVsDart: 1.50x'));
    expect(summary, contains('rustTotalIncrementalBuildSpeedupVsDart: 1.50x'));
    expect(summary, contains('rustWatchCollectionSpeedupVsDart: 1.54x'));
    expect(summary, contains('rustSpeedupVsDart: 1.50x'));
    expect(markdown, contains('# fast_build_runner watch benchmark'));
    expect(markdown, contains('- noise files per cycle: `3`'));
    expect(markdown, contains('- continuous scheduling: `true`'));
    expect(markdown, contains('- extra fixture models: `12`'));
    expect(markdown, contains('- post-build settle delay: `90 ms`'));
    expect(markdown, contains('- rust incremental build: `80 ms`'));
    expect(markdown, contains('- rust total incremental build: `80 ms`'));
    expect(markdown, contains('- rust watch collection: `260, 280 ms`'));
    expect(markdown, contains('- rust total watch collection: `540 ms`'));
    expect(markdown, contains('- rust daemon startup: `180 ms`'));
    expect(
      markdown,
      contains('- rust incremental build speedup vs dart: `1.50x`'),
    );
    expect(
      markdown,
      contains('- rust total incremental build speedup vs dart: `1.50x`'),
    );
    expect(
      markdown,
      contains('- rust watch collection speedup vs dart: `1.54x`'),
    );
    expect(markdown, contains('- rust speedup vs dart: `1.50x`'));
  });

  test(
    'watch benchmark adds interpretation warning when incremental gain is stronger than total gain',
    () {
      final result = FastWatchBenchmarkResult.fromRuns(
        incrementalCycles: 1,
        noiseFilesPerCycle: 0,
        continuousScheduling: false,
        extraFixtureModels: 0,
        settleBuildDelayMs: 0,
        dartSamples: const [
          FastWatchBenchmarkEngineResult(
            sourceEngine: 'dart',
            elapsedMilliseconds: 1000,
            result: FastWatchAlphaResult(
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
              initialBuild: FastBuildStepResult(
                name: 'initial',
                elapsedMilliseconds: 900,
                status: 'success',
                failureType: null,
                outputs: [],
                errors: [],
                generatedFileExists: true,
                generatedFileHasMutation: false,
              ),
              incrementalBuild: FastBuildStepResult(
                name: 'incremental-1',
                elapsedMilliseconds: 200,
                status: 'success',
                failureType: null,
                outputs: [],
                errors: [],
                generatedFileExists: true,
                generatedFileHasMutation: true,
              ),
              incrementalBuilds: [
                FastBuildStepResult(
                  name: 'incremental-1',
                  elapsedMilliseconds: 200,
                  status: 'success',
                  failureType: null,
                  outputs: [],
                  errors: [],
                  generatedFileExists: true,
                  generatedFileHasMutation: true,
                ),
              ],
            ),
          ),
        ],
        rustSamples: const [
          FastWatchBenchmarkEngineResult(
            sourceEngine: 'rust',
            elapsedMilliseconds: 950,
            result: FastWatchAlphaResult(
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
              initialBuild: FastBuildStepResult(
                name: 'initial',
                elapsedMilliseconds: 890,
                status: 'success',
                failureType: null,
                outputs: [],
                errors: [],
                generatedFileExists: true,
                generatedFileHasMutation: false,
              ),
              incrementalBuild: FastBuildStepResult(
                name: 'incremental-1',
                elapsedMilliseconds: 100,
                status: 'success',
                failureType: null,
                outputs: [],
                errors: [],
                generatedFileExists: true,
                generatedFileHasMutation: true,
              ),
              incrementalBuilds: [
                FastBuildStepResult(
                  name: 'incremental-1',
                  elapsedMilliseconds: 100,
                  status: 'success',
                  failureType: null,
                  outputs: [],
                  errors: [],
                  generatedFileExists: true,
                  generatedFileHasMutation: true,
                ),
              ],
            ),
          ),
        ],
      );

      expect(result.repeats, 1);
      expect(
        result.warnings,
        contains(
          'Incremental build speedup is stronger than total wall-clock speedup, which suggests initial build cost still dominates this fixture.',
        ),
      );
    },
  );

  test('watch benchmark chooses the median sample for each engine', () {
    final result = FastWatchBenchmarkResult.fromRuns(
      incrementalCycles: 1,
      noiseFilesPerCycle: 0,
      continuousScheduling: false,
      extraFixtureModels: 0,
      settleBuildDelayMs: 0,
      dartSamples: const [
        FastWatchBenchmarkEngineResult(
          sourceEngine: 'dart',
          elapsedMilliseconds: 1500,
          result: FastWatchAlphaResult(
            status: 'success',
            sourceEngine: 'dart',
            upstreamCommit: 'commit',
            generatedEntrypointPath: 'entrypoint',
            runDirectory: 'dart-1',
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
        FastWatchBenchmarkEngineResult(
          sourceEngine: 'dart',
          elapsedMilliseconds: 1000,
          result: FastWatchAlphaResult(
            status: 'success',
            sourceEngine: 'dart',
            upstreamCommit: 'commit',
            generatedEntrypointPath: 'entrypoint',
            runDirectory: 'dart-2',
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
        FastWatchBenchmarkEngineResult(
          sourceEngine: 'dart',
          elapsedMilliseconds: 1300,
          result: FastWatchAlphaResult(
            status: 'success',
            sourceEngine: 'dart',
            upstreamCommit: 'commit',
            generatedEntrypointPath: 'entrypoint',
            runDirectory: 'dart-3',
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
      ],
      rustSamples: const [
        FastWatchBenchmarkEngineResult(
          sourceEngine: 'rust',
          elapsedMilliseconds: 1100,
          result: FastWatchAlphaResult(
            status: 'success',
            sourceEngine: 'rust',
            upstreamCommit: 'commit',
            generatedEntrypointPath: 'entrypoint',
            runDirectory: 'rust-1',
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
        FastWatchBenchmarkEngineResult(
          sourceEngine: 'rust',
          elapsedMilliseconds: 900,
          result: FastWatchAlphaResult(
            status: 'success',
            sourceEngine: 'rust',
            upstreamCommit: 'commit',
            generatedEntrypointPath: 'entrypoint',
            runDirectory: 'rust-2',
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
        FastWatchBenchmarkEngineResult(
          sourceEngine: 'rust',
          elapsedMilliseconds: 1000,
          result: FastWatchAlphaResult(
            status: 'success',
            sourceEngine: 'rust',
            upstreamCommit: 'commit',
            generatedEntrypointPath: 'entrypoint',
            runDirectory: 'rust-3',
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
      ],
    );

    expect(result.repeats, 3);
    expect(result.dart.elapsedMilliseconds, 1300);
    expect(result.rust.elapsedMilliseconds, 1000);
  });
}
