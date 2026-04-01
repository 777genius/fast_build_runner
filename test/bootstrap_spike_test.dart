import 'dart:io';

import 'package:fast_build_runner_internal/fast_build_runner_internal.dart';
import 'package:test/test.dart';

void main() {
  test(
    'bootstrap spike succeeds on bundled json_serializable fixture',
    () async {
      final repoRoot = Directory.current.path;
      final result = await FastBootstrapSpikeRunner().run(
        FastBootstrapSpikeRequest(
          repoRoot: repoRoot,
          fixtureTemplatePath: '$repoRoot/fixtures/json_serializable_fixture',
          workDirectoryPath: '$repoRoot/.dart_tool/test_bootstrap_spike',
          keepRunDirectory: false,
        ),
      );

      expect(result.status, 'success');
      expect(result.upstreamCommit, pinnedBuildRunnerCommit);
      expect(result.initialBuild, isNotNull);
      expect(result.incrementalBuild, isNotNull);
      expect(result.initialBuild!.status, 'success');
      expect(result.incrementalBuild!.status, 'success');
      expect(result.initialBuild!.generatedFileExists, isTrue);
      expect(result.incrementalBuild!.generatedFileHasMutation, isTrue);
      expect(result.errors, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'bootstrap spike detects build script changes on incremental run',
    () async {
      final repoRoot = Directory.current.path;
      final result = await FastBootstrapSpikeRunner().run(
        FastBootstrapSpikeRequest(
          repoRoot: repoRoot,
          fixtureTemplatePath: '$repoRoot/fixtures/json_serializable_fixture',
          workDirectoryPath:
              '$repoRoot/.dart_tool/test_bootstrap_spike_build_script_change',
          keepRunDirectory: false,
          mutateBuildScriptBeforeIncremental: true,
        ),
      );

      expect(result.status, 'success');
      expect(result.initialBuild, isNotNull);
      expect(result.incrementalBuild, isNotNull);
      expect(result.initialBuild!.status, 'success');
      expect(result.incrementalBuild!.status, 'failure');
      expect(result.incrementalBuild!.failureType, 'buildScriptChanged');
      expect(result.errors, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
