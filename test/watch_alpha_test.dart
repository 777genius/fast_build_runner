import 'dart:io';

import 'package:fast_build_runner_internal/fast_build_runner_internal.dart';
import 'package:test/test.dart';

void main() {
  test('project mutation replacements tolerate CRLF line endings', () {
    const replacement = ProjectTextReplacement(
      from: '  final int? age;\n',
      to: '  final int? age;\n  final String? nickname;\n',
    );

    final updated = replacement.apply(
      'class Person {\r\n  final int? age;\r\n}\r\n',
      stepName: 'crlf profile',
    );

    expect(updated, 'class Person {\r\n  final int? age;\r\n  final String? nickname;\r\n}\r\n');
  });

  test(
    'watch alpha can drive mutations from an external mutation profile',
    () async {
      final repoRoot = Directory.current.path;
      final profileDirectory = Directory(
        '$repoRoot/.dart_tool/test_watch_alpha_profile',
      )..createSync(recursive: true);
      final profileFile = File('${profileDirectory.path}/person_profile.json');
      profileFile.writeAsStringSync('''
{
  "name": "fixture person profile",
  "sourceFileRelativePath": "lib/person.dart",
  "generatedFileRelativePath": "lib/person.g.dart",
  "steps": [
    {
      "name": "add nickname",
      "generatedMarkers": ["nickname"],
      "replacements": [
        {
          "from": "  const Person({required this.name, this.age});\\n",
          "to": "  const Person({required this.name, this.age, this.nickname});\\n"
        },
        {
          "from": "  final int? age;\\n",
          "to": "  final int? age;\\n  final String? nickname;\\n"
        }
      ]
    }
  ]
}
''');

      final result = await FastWatchAlphaRunner().run(
        FastWatchAlphaRequest(
          repoRoot: repoRoot,
          fixtureTemplatePath: '$repoRoot/fixtures/json_serializable_fixture',
          workDirectoryPath:
              '$repoRoot/.dart_tool/test_watch_alpha_profile_run',
          keepRunDirectory: false,
          mutationProfilePath: profileFile.path,
        ),
      );

      expect(result.status, 'success');
      expect(result.incrementalBuilds, hasLength(1));
      expect(result.incrementalBuild!.generatedFileHasMutation, isTrue);
      expect(result.errors, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'watch alpha can absorb unrelated noise files without widening merged updates',
    () async {
      final repoRoot = Directory.current.path;
      final result = await FastWatchAlphaRunner().run(
        FastWatchAlphaRequest(
          repoRoot: repoRoot,
          fixtureTemplatePath: '$repoRoot/fixtures/json_serializable_fixture',
          workDirectoryPath: '$repoRoot/.dart_tool/test_watch_alpha_noise',
          keepRunDirectory: false,
          noiseFilesPerCycle: 3,
        ),
      );

      expect(result.status, 'success');
      expect(result.incrementalBuilds, hasLength(1));
      expect(result.observedEventBatches, hasLength(1));
      expect(
        result.observedEventBatches.single.any(
          (event) => event.contains('.dart_tool/fast_build_runner_noise'),
        ),
        isTrue,
      );
      expect(result.mergedUpdateBatches, hasLength(1));
      expect(result.mergedUpdateBatches.single, hasLength(1));
      expect(
        result.mergedUpdateBatches.single.single,
        contains('bootstrap_json_fixture|lib/person.dart'),
      );
      expect(
        result.warnings,
        contains(
          'Watch alpha injected 3 unrelated noise file(s) on every incremental cycle.',
        ),
      );
      expect(result.errors, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

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
      expect(result.incrementalBuilds, hasLength(1));
      expect(result.watchCollectionMilliseconds, hasLength(1));
      expect(result.initialBuild!.status, 'success');
      expect(result.incrementalBuild!.status, 'success');
      expect(result.incrementalBuild!.generatedFileHasMutation, isTrue);
      expect(result.observedEvents, isNotEmpty);
      expect(result.mergedUpdates, hasLength(1));
      expect(result.observedEventBatches, hasLength(1));
      expect(result.mergedUpdateBatches, hasLength(1));
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
      expect(result.incrementalBuilds, hasLength(1));
      expect(result.initialBuild!.status, 'success');
      expect(result.incrementalBuild!.status, 'failure');
      expect(result.incrementalBuild!.failureType, 'buildScriptChanged');
      expect(result.mergedUpdates, isNotEmpty);
      expect(result.errors, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'watch alpha still surfaces buildScriptChanged when trust mode is enabled',
    () async {
      final repoRoot = Directory.current.path;
      final result = await FastWatchAlphaRunner().run(
        FastWatchAlphaRequest(
          repoRoot: repoRoot,
          fixtureTemplatePath: '$repoRoot/fixtures/json_serializable_fixture',
          workDirectoryPath:
              '$repoRoot/.dart_tool/test_watch_alpha_build_script_change_trusted',
          keepRunDirectory: false,
          trustBuildScriptFreshness: true,
          mutateBuildScriptBeforeIncremental: true,
        ),
      );

      expect(result.status, 'success');
      expect(result.initialBuild, isNotNull);
      expect(result.incrementalBuild, isNotNull);
      expect(result.incrementalBuild!.status, 'failure');
      expect(result.incrementalBuild!.failureType, 'buildScriptChanged');
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
      expect(result.incrementalBuilds, hasLength(1));
      expect(result.rustDaemonStartupMilliseconds, isNotNull);
      expect(result.watchCollectionMilliseconds, hasLength(1));
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

  test(
    'watch alpha can use the upstream build_runner watch loop as the baseline engine',
    () async {
      final repoRoot = Directory.current.path;
      final result = await FastWatchAlphaRunner().run(
        FastWatchAlphaRequest(
          repoRoot: repoRoot,
          fixtureTemplatePath: '$repoRoot/fixtures/json_serializable_fixture',
          workDirectoryPath: '$repoRoot/.dart_tool/test_watch_alpha_upstream',
          keepRunDirectory: false,
          sourceEngine: 'upstream',
        ),
      );

      expect(result.status, 'success');
      expect(result.sourceEngine, 'upstream');
      expect(result.initialBuild, isNotNull);
      expect(result.incrementalBuild, isNotNull);
      expect(result.incrementalBuilds, hasLength(1));
      expect(result.watchCollectionMilliseconds, isEmpty);
      expect(result.initialBuild!.status, 'success');
      expect(result.incrementalBuild!.status, 'success');
      expect(result.incrementalBuild!.generatedFileHasMutation, isTrue);
      expect(
        result.warnings,
        contains(
          'Watch alpha used the upstream build_runner watch loop as the baseline runtime.',
        ),
      );
      expect(result.errors, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'watch alpha can execute multiple incremental cycles before exiting',
    () async {
      final repoRoot = Directory.current.path;
      final result = await FastWatchAlphaRunner().run(
        FastWatchAlphaRequest(
          repoRoot: repoRoot,
          fixtureTemplatePath: '$repoRoot/fixtures/json_serializable_fixture',
          workDirectoryPath:
              '$repoRoot/.dart_tool/test_watch_alpha_multi_cycle',
          keepRunDirectory: false,
          incrementalCycles: 2,
        ),
      );

      expect(result.status, 'success');
      expect(result.sourceEngine, 'dart');
      expect(result.incrementalBuilds, hasLength(2));
      expect(result.watchCollectionMilliseconds, hasLength(2));
      expect(result.incrementalBuild?.name, 'incremental-2');
      expect(result.observedEventBatches, hasLength(2));
      expect(result.mergedUpdateBatches, hasLength(2));
      expect(
        result.mergedUpdateBatches.every(
          (batch) => batch.single.contains('lib/person.dart'),
        ),
        isTrue,
      );
      expect(
        result.warnings,
        contains('Watch alpha executed 2 incremental cycles before exiting.'),
      );
      expect(result.errors, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'watch alpha can execute more than three incremental cycles',
    () async {
      final repoRoot = Directory.current.path;
      final result = await FastWatchAlphaRunner().run(
        FastWatchAlphaRequest(
          repoRoot: repoRoot,
          fixtureTemplatePath: '$repoRoot/fixtures/json_serializable_fixture',
          workDirectoryPath:
              '$repoRoot/.dart_tool/test_watch_alpha_four_cycles',
          keepRunDirectory: false,
          incrementalCycles: 4,
        ),
      );

      expect(result.status, 'success');
      expect(result.incrementalBuilds, hasLength(4));
      expect(result.watchCollectionMilliseconds, hasLength(4));
      expect(result.incrementalBuild?.name, 'incremental-4');
      expect(result.incrementalBuilds.last.generatedFileHasMutation, isTrue);
      expect(result.errors, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'watch alpha resyncs from the filesystem when the source update is dropped',
    () async {
      final repoRoot = Directory.current.path;
      final result = await FastWatchAlphaRunner().run(
        FastWatchAlphaRequest(
          repoRoot: repoRoot,
          fixtureTemplatePath: '$repoRoot/fixtures/json_serializable_fixture',
          workDirectoryPath:
              '$repoRoot/.dart_tool/test_watch_alpha_resync_recovery',
          keepRunDirectory: false,
          simulateDroppedSourceUpdateOnIncremental: true,
        ),
      );

      expect(result.status, 'success');
      expect(result.incrementalBuilds, hasLength(1));
      expect(result.watchCollectionMilliseconds, hasLength(1));
      expect(result.incrementalBuild!.status, 'success');
      expect(result.incrementalBuild!.generatedFileHasMutation, isTrue);
      expect(
        result.warnings,
        contains(
          'The first incremental cycle intentionally dropped the source update before resolution to verify filesystem resync recovery.',
        ),
      );
      expect(
        result.warnings.any(
          (warning) =>
              warning.contains('incremental-1:') &&
              warning.contains(
                'Replaced watcher updates with filesystem resync updates.',
              ),
        ),
        isTrue,
      );
      expect(result.errors, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
