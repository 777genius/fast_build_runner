// ignore_for_file: implementation_imports, invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';

import 'package:build_runner/src/bootstrap/processes.dart';
import 'package:build_runner/src/internal.dart';

import 'bootstrap_spike_result.dart';
import 'fast_spike_session.dart';
import 'fast_watch_alpha_session.dart';
import 'upstream_pin.dart';
import 'watch_alpha_result.dart';

class FastSpikeChildRunner {
  Future<void> run(List<String> args, BuilderFactories builderFactories) async {
    final message = await ChildProcess.receive();
    buildProcessState.deserializeAndSet(message);
    final argMap = _parseArgs(args);
    final mode = argMap['mode'] ?? 'bootstrap-spike';
    final projectDirectory = argMap['project-dir'];
    final sourceFile = argMap['source-file'];
    final generatedFile = argMap['generated-file'];
    final packageName = argMap['package-name'];
    final entrypointScript = argMap['entrypoint-script'];
    final sourceEngine = argMap['source-engine'] ?? 'dart';
    final incrementalCycles =
        int.tryParse(argMap['incremental-cycles'] ?? '') ?? 1;
    final noiseFilesPerCycle =
        int.tryParse(argMap['noise-files-per-cycle'] ?? '') ?? 0;
    final continuousScheduling = argMap['continuous-scheduling'] == 'true';
    final settleBuildDelayMs =
        int.tryParse(argMap['settle-build-delay-ms'] ?? '') ?? 0;
    final trustBuildScriptFreshness =
        argMap['trust-build-script-freshness'] == 'true';
    final rustDaemonDirectory = argMap['rust-daemon-dir'];
    final mutationProfilePath = argMap['mutation-profile'];
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
    final simulateDroppedSourceUpdateOnIncremental =
        argMap['simulate-dropped-source-update-on-incremental'] == 'true';

    Directory.current = resolvedProjectDirectory;
    Object result;
    try {
      switch (mode) {
        case 'watch-alpha':
          result =
              await FastWatchAlphaSession(
                builderFactories: builderFactories,
                upstreamCommit: pinnedBuildRunnerCommit,
              ).run(
                sourceEngine: sourceEngine,
                incrementalCycles: incrementalCycles,
                noiseFilesPerCycle: noiseFilesPerCycle,
                continuousScheduling: continuousScheduling,
                settleBuildDelayMs: settleBuildDelayMs,
                trustBuildScriptFreshness: trustBuildScriptFreshness,
                rustDaemonDirectory: rustDaemonDirectory,
                packageName: resolvedPackageName,
                sourceFileRelativePath: resolvedSourceFile,
                generatedFileRelativePath: resolvedGeneratedFile,
                generatedEntrypointPath: resolvedEntrypointScript,
                runDirectory: resolvedProjectDirectory,
                mutationProfilePath: mutationProfilePath,
                mutateBuildScriptBeforeIncremental:
                    mutateBuildScriptBeforeIncremental,
                simulateDroppedSourceUpdateOnIncremental:
                    simulateDroppedSourceUpdateOnIncremental,
              );
          break;
        case 'bootstrap-spike':
        default:
          result =
              await FastSpikeSession(
                builderFactories: builderFactories,
                upstreamCommit: pinnedBuildRunnerCommit,
              ).run(
                packageName: resolvedPackageName,
                sourceFileRelativePath: resolvedSourceFile,
                generatedFileRelativePath: resolvedGeneratedFile,
                generatedEntrypointPath: resolvedEntrypointScript,
                runDirectory: resolvedProjectDirectory,
                mutateBuildScriptBeforeIncremental:
                    mutateBuildScriptBeforeIncremental,
              );
          break;
      }
    } catch (error) {
      result = mode == 'watch-alpha'
          ? FastWatchAlphaResult(
              status: 'failure',
              sourceEngine: sourceEngine,
              upstreamCommit: pinnedBuildRunnerCommit,
              generatedEntrypointPath: resolvedEntrypointScript,
              runDirectory: resolvedProjectDirectory,
              warnings: const [],
              errors: ['$error'],
              observedEvents: const [],
              mergedUpdates: const [],
              observedEventBatches: const [],
              mergedUpdateBatches: const [],
              initialBuild: null,
              incrementalBuild: null,
              incrementalBuilds: const [],
            )
          : FastBootstrapSpikeResult(
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

    final exitCode = switch (result) {
      FastWatchAlphaResult result => result.exitCode,
      FastBootstrapSpikeResult result => result.exitCode,
      _ => 1,
    };
    final payload = switch (result) {
      FastWatchAlphaResult result => result.toJson(),
      FastBootstrapSpikeResult result => result.toJson(),
      _ => <String, Object?>{
        'status': 'failure',
        'errors': ['Unknown child runner result type.'],
      },
    };

    await ChildProcess.exitWithMessage(
      exitCode: exitCode,
      message: jsonEncode(payload),
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
