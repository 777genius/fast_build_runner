// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'package:build_runner/src/bootstrap/processes.dart';

import 'bootstrap_spike_request.dart';
import 'bootstrap_spike_result.dart';
import 'fast_bootstrap_generator.dart';
import 'upstream_pin.dart';

class FastBootstrapSpikeRunner {
  Future<FastBootstrapSpikeResult> run(FastBootstrapSpikeRequest request) async {
    final upstreamDir = p.join(request.repoRoot, 'research', 'dart-build');
    final actualCommit = await _readGitCommit(upstreamDir);
    if (actualCommit != pinnedBuildRunnerCommit) {
      return FastBootstrapSpikeResult(
        status: 'failure',
        upstreamCommit: actualCommit,
        generatedEntrypointPath: '',
        runDirectory: '',
        warnings: const [],
        errors: [
          'Pinned build_runner commit mismatch. Expected '
              '$pinnedBuildRunnerCommit but found $actualCommit.',
        ],
        initialBuild: null,
        incrementalBuild: null,
      );
    }

    final fixtureTemplateDir = Directory(request.fixtureTemplatePath);
    if (!fixtureTemplateDir.existsSync()) {
      return FastBootstrapSpikeResult(
        status: 'failure',
        upstreamCommit: actualCommit,
        generatedEntrypointPath: '',
        runDirectory: '',
        warnings: const [],
        errors: ['Fixture template does not exist: ${fixtureTemplateDir.path}'],
        initialBuild: null,
        incrementalBuild: null,
      );
    }

    final runDirectory = await _createRunDirectory(request.workDirectoryPath);
    final entrypointPath = p.join(
      runDirectory.path,
      '.dart_tool',
      'build',
      'entrypoint',
      'fast_build_runner_spike.dart',
    );

    try {
      await _copyDirectory(fixtureTemplateDir, runDirectory);
      await _runPubGet(runDirectory.path);

      final packageName = _readPackageName(
        File(p.join(runDirectory.path, 'pubspec.yaml')),
      );
      await FastBootstrapGenerator().generate(
        projectDirectory: runDirectory.path,
        outputPath: entrypointPath,
        internalLibraryPath: p.join(
          request.repoRoot,
          'packages',
          'fast_build_runner_internal',
          'lib',
          'fast_build_runner_internal.dart',
        ),
        upstreamCommit: actualCommit,
      );

      final packageConfigUri = Uri.file(
        p.join(runDirectory.path, '.dart_tool', 'package_config.json'),
      ).toString();
      final parentMessage = jsonEncode({'packageConfigUri': packageConfigUri});

      final previousCurrentDirectory = Directory.current;
      Directory.current = runDirectory;
      try {
        final childResult = await ParentProcess.runAndSend(
          script: entrypointPath,
          arguments: [
            '--project-dir=${runDirectory.path}',
            '--package-name=$packageName',
            '--source-file=lib/person.dart',
            '--generated-file=lib/person.g.dart',
          ],
          message: parentMessage,
          jitVmArgs: const [],
        );
        final decoded =
            jsonDecode(childResult.message) as Map<String, Object?>;
        return FastBootstrapSpikeResult.fromJson(decoded);
      } finally {
        Directory.current = previousCurrentDirectory;
      }
    } catch (error) {
      return FastBootstrapSpikeResult(
        status: 'failure',
        upstreamCommit: actualCommit,
        generatedEntrypointPath: entrypointPath,
        runDirectory: runDirectory.path,
        warnings: const [],
        errors: ['$error'],
        initialBuild: null,
        incrementalBuild: null,
      );
    } finally {
      if (!request.keepRunDirectory) {
        final resultFile = File(p.join(runDirectory.path, 'lib', 'person.g.dart'));
        final keepForInspection = !resultFile.existsSync();
        if (!keepForInspection && runDirectory.existsSync()) {
          await runDirectory.delete(recursive: true);
        }
      }
    }
  }

  Future<String> _readGitCommit(String directory) async {
    final result = await Process.run('git', [
      '-C',
      directory,
      'rev-parse',
      'HEAD',
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'Unable to read git commit in $directory: ${result.stderr}',
      );
    }
    return (result.stdout as String).trim();
  }

  Future<Directory> _createRunDirectory(String workDirectoryPath) async {
    final root = Directory(workDirectoryPath)..createSync(recursive: true);
    final runDir = Directory(
      p.join(root.path, 'run-${DateTime.now().millisecondsSinceEpoch}'),
    );
    runDir.createSync(recursive: true);
    return runDir;
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (final entity in source.list(recursive: false)) {
      final targetPath = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        final targetDirectory = Directory(targetPath)..createSync(recursive: true);
        await _copyDirectory(entity, targetDirectory);
      } else if (entity is File) {
        await File(entity.path).copy(targetPath);
      }
    }
  }

  Future<void> _runPubGet(String projectDirectory) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['pub', 'get'],
      workingDirectory: projectDirectory,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'dart pub get failed in $projectDirectory\n'
        'stdout:\n${result.stdout}\n'
        'stderr:\n${result.stderr}',
      );
    }
  }

  String _readPackageName(File pubspecFile) {
    final yaml = loadYaml(pubspecFile.readAsStringSync()) as YamlMap;
    final name = yaml['name'];
    if (name is! String || name.isEmpty) {
      throw StateError('Fixture pubspec is missing a valid package name.');
    }
    return name;
  }
}
