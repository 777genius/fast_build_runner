import 'dart:io';

import 'package:fast_build_runner_internal/fast_build_runner_internal.dart';
import 'package:test/test.dart';

void main() {
  test(
    'watch alpha observes file changes and rebuilds incrementally',
    () async {
      final repoRoot = Directory.current.path;
      final result = await FastWatchAlphaRunner().run(
        FastWatchAlphaRequest(
          repoRoot: repoRoot,
          fixtureTemplatePath: '$repoRoot/fixtures/json_serializable_fixture',
          workDirectoryPath: '$repoRoot/.dart_tool/test_watch_alpha',
          keepRunDirectory: false,
        ),
      );

      expect(result.status, 'success');
      expect(result.sourceEngine, 'dart');
      expect(result.upstreamCommit, pinnedBuildRunnerCommit);
      expect(result.initialBuild, isNotNull);
      expect(result.incrementalBuild, isNotNull);
      expect(result.initialBuild!.status, 'success');
      expect(result.incrementalBuild!.status, 'success');
      expect(result.incrementalBuild!.generatedFileHasMutation, isTrue);
      expect(result.observedEvents, isNotEmpty);
      expect(result.mergedUpdates, hasLength(1));
      expect(
        result.mergedUpdates.single,
        contains('bootstrap_json_fixture|lib/person.dart'),
      );
      expect(result.errors, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'watch alpha surfaces buildScriptChanged when the generated entrypoint changes',
    () async {
      final repoRoot = Directory.current.path;
      final result = await FastWatchAlphaRunner().run(
        FastWatchAlphaRequest(
          repoRoot: repoRoot,
          fixtureTemplatePath: '$repoRoot/fixtures/json_serializable_fixture',
          workDirectoryPath:
              '$repoRoot/.dart_tool/test_watch_alpha_build_script_change',
          keepRunDirectory: false,
          mutateBuildScriptBeforeIncremental: true,
        ),
      );

      expect(result.status, 'success');
      expect(result.sourceEngine, 'dart');
      expect(result.initialBuild, isNotNull);
      expect(result.incrementalBuild, isNotNull);
      expect(result.initialBuild!.status, 'success');
      expect(result.incrementalBuild!.status, 'failure');
      expect(result.incrementalBuild!.failureType, 'buildScriptChanged');
      expect(result.mergedUpdates, isNotEmpty);
      expect(result.errors, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'watch alpha can use the Rust daemon as the source engine',
    () async {
      final repoRoot = Directory.current.path;
      final result = await FastWatchAlphaRunner().run(
        FastWatchAlphaRequest(
          repoRoot: repoRoot,
          fixtureTemplatePath: '$repoRoot/fixtures/json_serializable_fixture',
          workDirectoryPath: '$repoRoot/.dart_tool/test_watch_alpha_rust',
          keepRunDirectory: false,
          sourceEngine: 'rust',
        ),
      );

      expect(result.status, 'success');
      expect(result.sourceEngine, 'rust');
      expect(result.initialBuild, isNotNull);
      expect(result.incrementalBuild, isNotNull);
      expect(result.initialBuild!.status, 'success');
      expect(result.incrementalBuild!.status, 'success');
      expect(result.incrementalBuild!.generatedFileHasMutation, isTrue);
      expect(
        result.observedEvents.any((event) => event.contains('lib/person.dart')),
        isTrue,
      );
      expect(result.mergedUpdates, hasLength(1));
      expect(
        result.mergedUpdates.single,
        contains('bootstrap_json_fixture|lib/person.dart'),
      );
      expect(
        result.warnings,
        contains(
          'Watch alpha used the Rust daemon as the filesystem event source.',
        ),
      );
      expect(result.errors, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
