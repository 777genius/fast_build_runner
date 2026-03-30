// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:io';

import 'package:build_runner/src/bootstrap/processes.dart';
import 'package:build_runner/src/constants.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'fast_bootstrap_generator.dart';
import 'fast_bootstrapper.dart';
import 'upstream_pin.dart';
import 'watch_alpha_request.dart';
import 'watch_alpha_result.dart';

class FastWatchAlphaRunner {
  Future<FastWatchAlphaResult> run(FastWatchAlphaRequest request) async {
    final upstreamDir = p.join(request.repoRoot, 'research', 'dart-build');
    final actualCommit = await _readGitCommit(upstreamDir);
    if (actualCommit != pinnedBuildRunnerCommit) {
      return FastWatchAlphaResult(
        status: 'failure',
        sourceEngine: request.sourceEngine,
        upstreamCommit: actualCommit,
        generatedEntrypointPath: '',
        runDirectory: '',
        warnings: const [],
        errors: [
          'Pinned build_runner commit mismatch. Expected '
              '$pinnedBuildRunnerCommit but found $actualCommit.',
        ],
        observedEvents: const [],
        mergedUpdates: const [],
        observedEventBatches: const [],
        mergedUpdateBatches: const [],
        initialBuild: null,
        incrementalBuild: null,
        incrementalBuilds: const [],
      );
    }

    if (request.incrementalCycles < 1) {
      return FastWatchAlphaResult(
        status: 'failure',
        sourceEngine: request.sourceEngine,
        upstreamCommit: actualCommit,
        generatedEntrypointPath: '',
        runDirectory: '',
        warnings: const [],
        errors: const ['Watch alpha requires at least one incremental cycle.'],
        observedEvents: const [],
        mergedUpdates: const [],
        observedEventBatches: const [],
        mergedUpdateBatches: const [],
        initialBuild: null,
        incrementalBuild: null,
        incrementalBuilds: const [],
      );
    }
    if (request.noiseFilesPerCycle < 0) {
      return FastWatchAlphaResult(
        status: 'failure',
        sourceEngine: request.sourceEngine,
        upstreamCommit: actualCommit,
        generatedEntrypointPath: '',
        runDirectory: '',
        warnings: const [],
        errors: const ['Watch alpha requires noiseFilesPerCycle >= 0.'],
        observedEvents: const [],
        mergedUpdates: const [],
        observedEventBatches: const [],
        mergedUpdateBatches: const [],
        initialBuild: null,
        incrementalBuild: null,
        incrementalBuilds: const [],
      );
    }
    if (request.extraFixtureModels < 0) {
      return FastWatchAlphaResult(
        status: 'failure',
        sourceEngine: request.sourceEngine,
        upstreamCommit: actualCommit,
        generatedEntrypointPath: '',
        runDirectory: '',
        warnings: const [],
        errors: const ['Watch alpha requires extraFixtureModels >= 0.'],
        observedEvents: const [],
        mergedUpdates: const [],
        observedEventBatches: const [],
        mergedUpdateBatches: const [],
        initialBuild: null,
        incrementalBuild: null,
        incrementalBuilds: const [],
      );
    }
    if (request.settleBuildDelayMs < 0) {
      return FastWatchAlphaResult(
        status: 'failure',
        sourceEngine: request.sourceEngine,
        upstreamCommit: actualCommit,
        generatedEntrypointPath: '',
        runDirectory: '',
        warnings: const [],
        errors: const ['Watch alpha requires settleBuildDelayMs >= 0.'],
        observedEvents: const [],
        mergedUpdates: const [],
        observedEventBatches: const [],
        mergedUpdateBatches: const [],
        initialBuild: null,
        incrementalBuild: null,
        incrementalBuilds: const [],
      );
    }

    final fixtureTemplateDir = Directory(request.fixtureTemplatePath);
    if (!fixtureTemplateDir.existsSync()) {
      return FastWatchAlphaResult(
        status: 'failure',
        sourceEngine: request.sourceEngine,
        upstreamCommit: actualCommit,
        generatedEntrypointPath: '',
        runDirectory: '',
        warnings: const [],
        errors: ['Fixture template does not exist: ${fixtureTemplateDir.path}'],
        observedEvents: const [],
        mergedUpdates: const [],
        observedEventBatches: const [],
        mergedUpdateBatches: const [],
        initialBuild: null,
        incrementalBuild: null,
        incrementalBuilds: const [],
      );
    }

    final runDirectory = await _createRunDirectory(request.workDirectoryPath);
    final entrypointPath = p.join(runDirectory.path, entrypointScriptPath);

    try {
      await _copyDirectory(fixtureTemplateDir, runDirectory);
      if (request.extraFixtureModels > 0) {
        _expandFixtureModelSet(runDirectory.path, request.extraFixtureModels);
      }
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
        internalLibraryPath: p.join(
          request.repoRoot,
          'packages',
          'fast_build_runner_internal',
          'lib',
          'src',
          'fast_spike_child_runner.dart',
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
            '--mode=watch-alpha',
            '--project-dir=${runDirectory.path}',
            '--package-name=$packageName',
            '--source-file=lib/person.dart',
            '--generated-file=lib/person.g.dart',
            '--entrypoint-script=$entrypointPath',
            '--source-engine=${request.sourceEngine}',
            '--incremental-cycles=${request.incrementalCycles}',
            '--noise-files-per-cycle=${request.noiseFilesPerCycle}',
            '--continuous-scheduling=${request.continuousScheduling}',
            '--settle-build-delay-ms=${request.settleBuildDelayMs}',
            '--rust-daemon-dir=${p.join(request.repoRoot, 'native', 'daemon')}',
            if (request.mutateBuildScriptBeforeIncremental)
              '--mutate-build-script-before-incremental=true',
            if (request.simulateDroppedSourceUpdateOnIncremental)
              '--simulate-dropped-source-update-on-incremental=true',
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
        return FastWatchAlphaResult.fromJson(decoded);
      } finally {
        Directory.current = previousCurrentDirectory;
      }
    } catch (error) {
      return FastWatchAlphaResult(
        status: 'failure',
        sourceEngine: request.sourceEngine,
        upstreamCommit: actualCommit,
        generatedEntrypointPath: entrypointPath,
        runDirectory: runDirectory.path,
        warnings: const [],
        errors: ['$error'],
        observedEvents: const [],
        mergedUpdates: const [],
        observedEventBatches: const [],
        mergedUpdateBatches: const [],
        initialBuild: null,
        incrementalBuild: null,
        incrementalBuilds: const [],
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
        final targetDirectory = Directory(targetPath)
          ..createSync(recursive: true);
        await _copyDirectory(entity, targetDirectory);
      } else if (entity is File) {
        await File(entity.path).copy(targetPath);
      }
    }
  }

  void _expandFixtureModelSet(String projectDirectory, int extraFixtureModels) {
    final modelsDirectory = Directory(
      p.join(projectDirectory, 'lib', 'generated_models'),
    )..createSync(recursive: true);
    for (var index = 1; index <= extraFixtureModels; index++) {
      final className = 'GeneratedModel$index';
      final baseName = _snakeCase(className);
      final fileName = '$baseName.dart';
      final file = File(p.join(modelsDirectory.path, fileName));
      file.writeAsStringSync(_generatedFixtureModelSource(className, baseName));
    }
  }

  String _generatedFixtureModelSource(String className, String baseName) =>
      '''
import 'package:json_annotation/json_annotation.dart';

part '$baseName.g.dart';

@JsonSerializable()
class $className {
  final String id;
  final int? count;
  final bool? isEnabled;

  const $className({
    required this.id,
    this.count,
    this.isEnabled,
  });

  factory $className.fromJson(Map<String, dynamic> json) =>
      _\$${className}FromJson(json);

  Map<String, dynamic> toJson() => _\$${className}ToJson(this);
}
''';

  String _snakeCase(String input) {
    final buffer = StringBuffer();
    for (var index = 0; index < input.length; index++) {
      final char = input[index];
      final isUppercase =
          char.toUpperCase() == char && char.toLowerCase() != char;
      if (isUppercase && index > 0) {
        buffer.write('_');
      }
      buffer.write(char.toLowerCase());
    }
    return buffer.toString();
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
    final devDependenciesPatched = original.replaceFirst(
      RegExp(r'^dev_dependencies:\n', multiLine: true),
      'dev_dependencies:\n  build_runner: any\n',
    );
    final patched = StringBuffer()
      ..writeln(devDependenciesPatched.trimRight())
      ..writeln()
      ..writeln('# fast_build_runner prepared fixture')
      ..writeln('dependency_overrides:')
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
    pubspecFile.writeAsStringSync(patched.toString());
  }
}
