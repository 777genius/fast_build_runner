// ignore_for_file: implementation_imports, invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';

import 'package:build_runner/src/bootstrap/processes.dart';
import 'package:build_runner/src/internal.dart';

import 'bootstrap_spike_result.dart';
import 'fast_spike_session.dart';
import 'upstream_pin.dart';

class FastSpikeChildRunner {
  Future<void> run(List<String> args, BuilderFactories builderFactories) async {
    final message = await ChildProcess.receive();
    buildProcessState.deserializeAndSet(message);
    final argMap = _parseArgs(args);
    final projectDirectory = argMap['project-dir'];
    final sourceFile = argMap['source-file'];
    final generatedFile = argMap['generated-file'];
    final packageName = argMap['package-name'];
    final entrypointScript = argMap['entrypoint-script'];
    if (projectDirectory == null ||
        sourceFile == null ||
        generatedFile == null ||
        packageName == null ||
        entrypointScript == null) {
      await ChildProcess.exitWithMessage(
        exitCode: 64,
        message: jsonEncode({
          'status': 'failure',
          'upstreamCommit': pinnedBuildRunnerCommit,
          'generatedEntrypointPath': Platform.script.toFilePath(),
          'runDirectory': projectDirectory ?? '',
          'warnings': const <String>[],
          'errors': const ['Missing required child runner arguments.'],
          'initialBuild': null,
          'incrementalBuild': null,
        }),
      );
    }

    final resolvedProjectDirectory = projectDirectory;
    final resolvedSourceFile = sourceFile;
    final resolvedGeneratedFile = generatedFile;
    final resolvedPackageName = packageName;
    final resolvedEntrypointScript = entrypointScript;
    final mutateBuildScriptBeforeIncremental =
        argMap['mutate-build-script-before-incremental'] == 'true';

    Directory.current = resolvedProjectDirectory;
    FastBootstrapSpikeResult result;
    try {
      result = await FastSpikeSession(
        builderFactories: builderFactories,
        upstreamCommit: pinnedBuildRunnerCommit,
      ).run(
        packageName: resolvedPackageName,
        sourceFileRelativePath: resolvedSourceFile,
        generatedFileRelativePath: resolvedGeneratedFile,
        generatedEntrypointPath: resolvedEntrypointScript,
        runDirectory: resolvedProjectDirectory,
        mutateBuildScriptBeforeIncremental: mutateBuildScriptBeforeIncremental,
      );
    } catch (error) {
      result = FastBootstrapSpikeResult(
        status: 'failure',
        upstreamCommit: pinnedBuildRunnerCommit,
        generatedEntrypointPath: resolvedEntrypointScript,
        runDirectory: resolvedProjectDirectory,
        warnings: const [],
        errors: ['$error'],
        initialBuild: null,
        incrementalBuild: null,
      );
    }

    await ChildProcess.exitWithMessage(
      exitCode: result.exitCode,
      message: jsonEncode(result.toJson()),
    );
  }

  Map<String, String> _parseArgs(List<String> args) {
    final result = <String, String>{};
    for (final arg in args) {
      if (!arg.startsWith('--')) continue;
      final split = arg.substring(2).split('=');
      if (split.length < 2) continue;
      result[split.first] = split.sublist(1).join('=');
    }
    return result;
  }
}
