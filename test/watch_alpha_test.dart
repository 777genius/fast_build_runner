import 'dart:io';

import 'package:fast_build_runner_internal/fast_build_runner_internal.dart';
import 'package:test/test.dart';

void main() {
  test('watch alpha observes file changes and rebuilds incrementally', () async {
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
    expect(result.upstreamCommit, pinnedBuildRunnerCommit);
    expect(result.initialBuild, isNotNull);
    expect(result.incrementalBuild, isNotNull);
    expect(result.initialBuild!.status, 'success');
    expect(result.incrementalBuild!.status, 'success');
    expect(result.incrementalBuild!.generatedFileHasMutation, isTrue);
    expect(result.observedEvents, isNotEmpty);
    expect(result.errors, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
