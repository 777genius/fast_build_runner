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
}
