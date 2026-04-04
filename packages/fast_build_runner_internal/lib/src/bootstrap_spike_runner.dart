// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'package:build_runner/src/constants.dart';
import 'package:build_runner/src/bootstrap/processes.dart';

import 'bootstrap_spike_request.dart';
import 'bootstrap_spike_result.dart';
import 'fast_bootstrap_generator.dart';
import 'fast_bootstrapper.dart';
import 'project_fixture_copy.dart';
import 'upstream_pin.dart';

class FastBootstrapSpikeRunner {
  Future<FastBootstrapSpikeResult> run(
    FastBootstrapSpikeRequest request,
  ) async {
    final upstreamDir = p.join(request.repoRoot, 'research', 'dart-build');
    final actualCommit = await _resolveUpstreamMarker(upstreamDir);
    if (actualCommit != hostedBuildRunnerMarker &&
        actualCommit != pinnedBuildRunnerCommit) {
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
    final entrypointPath = p.join(runDirectory.path, entrypointScriptPath);

    try {
      await copyProjectFixture(fixtureTemplateDir, runDirectory);
      await _prepareFixturePubspec(
        fixturePubspecPath: p.join(runDirectory.path, 'pubspec.yaml'),
        repoRoot: request.repoRoot,
      );
      await _runPubGet(runDirectory.path);

      final packageName = _readPackageName(
        File(p.join(runDirectory.path, 'pubspec.yaml')),
      );
      await FastBootstrapGenerator().generate(
        projectDirectory: runDirectory.path,
        outputPath: entrypointPath,
        internalLibraryImport: _internalRunnerImport(
          request.internalPackageRootPath,
        ),
        upstreamCommit: actualCommit,
      );
      final bootstrapper = FastBootstrapper(
        workspace: false,
        compileAot: false,
      );
      final compileResult = await _withWorkingDirectory(
        runDirectory.path,
        bootstrapper.ensureCompiled,
      );
      if (!compileResult.succeeded) {
        throw StateError(
          'Failed to compile generated entrypoint.\n${compileResult.messages ?? ''}',
        );
      }

      final packageConfigUri = Uri.file(
        p.join(runDirectory.path, '.dart_tool', 'package_config.json'),
      ).toString();
      final parentMessage = jsonEncode({'packageConfigUri': packageConfigUri});

      final previousCurrentDirectory = Directory.current;
      Directory.current = runDirectory;
      try {
        final childResult = await ParentProcess.runAndSend(
          script: p.join(
            runDirectory.path,
            bootstrapper.entrypointExecutablePath,
          ),
          arguments: [
            '--project-dir=${runDirectory.path}',
            '--package-name=$packageName',
            '--source-file=lib/person.dart',
            '--generated-file=lib/person.g.dart',
            '--entrypoint-script=$entrypointPath',
            if (request.mutateBuildScriptBeforeIncremental)
              '--mutate-build-script-before-incremental=true',
          ],
          message: parentMessage,
          jitVmArgs: const [],
        );
        if (childResult.message.trim().isEmpty) {
          throw StateError(
            'Child process exited with code ${childResult.exitCode} without a result payload.',
          );
        }
        final decoded = jsonDecode(childResult.message) as Map<String, Object?>;
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
        final resultFile = File(
          p.join(runDirectory.path, 'lib', 'person.g.dart'),
        );
        final keepForInspection = !resultFile.existsSync();
        if (!keepForInspection && runDirectory.existsSync()) {
          await runDirectory.delete(recursive: true);
        }
      }
    }
  }

  Future<T> _withWorkingDirectory<T>(
    String directory,
    Future<T> Function() action,
  ) async {
    final previous = Directory.current;
    Directory.current = Directory(directory);
    try {
      return await action();
    } finally {
      Directory.current = previous;
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

  Future<String> _resolveUpstreamMarker(String upstreamDir) async {
    if (!Directory(upstreamDir).existsSync()) {
      return hostedBuildRunnerMarker;
    }
    return _readGitCommit(upstreamDir);
  }

  String _internalRunnerImport(String internalPackageRootPath) {
    final internalLibrary = File(
      p.join(
        internalPackageRootPath,
        'lib',
        'src',
        'fast_spike_child_runner.dart',
      ),
    );
    if (!internalLibrary.existsSync()) {
      throw StateError(
        'Internal runner library does not exist: ${internalLibrary.path}',
      );
    }
    return internalLibrary.uri.toString();
  }

  Future<Directory> _createRunDirectory(String workDirectoryPath) async {
    final root = Directory(workDirectoryPath)..createSync(recursive: true);
    final runDir = Directory(
      p.join(root.path, 'run-${DateTime.now().millisecondsSinceEpoch}'),
    );
    runDir.createSync(recursive: true);
    return runDir;
  }

  Future<void> _runPubGet(String projectDirectory) async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'pub',
      'get',
    ], workingDirectory: projectDirectory);
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

  Future<void> _prepareFixturePubspec({
    required String fixturePubspecPath,
    required String repoRoot,
  }) async {
    final pubspecFile = File(fixturePubspecPath);
    final original = pubspecFile.readAsStringSync();
    if (original.contains('fast_build_runner prepared fixture')) {
      return;
    }
    final devDependenciesPatched = _ensureBuildRunnerDevDependency(original);
    final hasResearchCheckout = Directory(
      p.join(repoRoot, 'research', 'dart-build'),
    ).existsSync();
    final patched = StringBuffer()
      ..writeln(devDependenciesPatched.trimRight())
      ..writeln()
      ..writeln('# fast_build_runner prepared fixture')
      ..write(_dependencyOverridesYaml(
        repoRoot: repoRoot,
        hasResearchCheckout: hasResearchCheckout,
      ));
    pubspecFile.writeAsStringSync(patched.toString());
  }

  String _ensureBuildRunnerDevDependency(String original) {
    if (RegExp(r'^  build_runner\s*:', multiLine: true).hasMatch(original)) {
      return original;
    }
    if (RegExp(r'^dev_dependencies:\n', multiLine: true).hasMatch(original)) {
      return original.replaceFirst(
        RegExp(r'^dev_dependencies:\n', multiLine: true),
        'dev_dependencies:\n  build_runner: any\n',
      );
    }
    return '${original.trimRight()}\n\ndev_dependencies:\n  build_runner: any\n';
  }

  String _dependencyOverridesYaml({
    required String repoRoot,
    required bool hasResearchCheckout,
  }) {
    if (!hasResearchCheckout) {
      return '';
    }

    final buffer = StringBuffer()..writeln('dependency_overrides:');
    if (hasResearchCheckout) {
      buffer
        ..writeln('  build:')
        ..writeln(
          "    path: ${p.join(repoRoot, 'research', 'dart-build', 'build')}",
        )
        ..writeln('  build_config:')
        ..writeln(
          "    path: ${p.join(repoRoot, 'research', 'dart-build', 'build_config')}",
        )
        ..writeln('  build_daemon:')
        ..writeln(
          "    path: ${p.join(repoRoot, 'research', 'dart-build', 'build_daemon')}",
        )
        ..writeln('  build_runner:')
        ..writeln(
          "    path: ${p.join(repoRoot, 'research', 'dart-build', 'build_runner')}",
        );
    }
    return buffer.toString();
  }
}
