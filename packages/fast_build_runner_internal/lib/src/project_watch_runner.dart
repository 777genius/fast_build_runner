// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build_runner/src/constants.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'fast_bootstrap_generator.dart';
import 'fast_bootstrapper.dart';
import 'project_watch_request.dart';
import 'upstream_pin.dart';

const _liveRestartExitCode = 75;
const _generatedOverridesMarker = '# fast_build_runner generated overrides';

class FastProjectWatchRunner {
  Future<int> run(FastProjectWatchRequest request) async {
    final projectDirectory = Directory(request.projectDirectoryPath).absolute;
    final pubspecFile = File(p.join(projectDirectory.path, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      stderr.writeln(
        'fast_build_runner: no pubspec.yaml found in ${projectDirectory.path}.',
      );
      return 64;
    }
    if (!_hasBuildRunnerDependency(pubspecFile)) {
      stderr.writeln(
        'fast_build_runner: this project does not declare build_runner in dependencies/dev_dependencies.',
      );
      stderr.writeln(
        'fast_build_runner: add build_runner first, then run `fast_build_runner watch`.',
      );
      return 64;
    }

    final upstreamDir = p.join(request.repoRoot, 'research', 'dart-build');
    final upstreamMarker = await _resolveUpstreamMarker(upstreamDir);
    final overridesManager = _ProjectPubspecOverridesManager(
      projectDirectoryPath: projectDirectory.path,
    );

    await overridesManager.apply(
      _overrideEntries(
        repoRoot: request.repoRoot,
        hasResearchCheckout: Directory(upstreamDir).existsSync(),
      ),
    );

    Process? childProcess;
    StreamSubscription<ProcessSignal>? sigintSubscription;
    StreamSubscription<ProcessSignal>? sigtermSubscription;
    final stopCompleter = Completer<int>();

    Future<void> stopChild(int signalExitCode) async {
      if (stopCompleter.isCompleted) {
        return;
      }
      stopCompleter.complete(signalExitCode);
      childProcess?.kill(ProcessSignal.sigterm);
    }

    try {
      sigintSubscription = ProcessSignal.sigint.watch().listen((_) {
        unawaited(stopChild(130));
      });
      if (!Platform.isWindows) {
        sigtermSubscription = ProcessSignal.sigterm.watch().listen((_) {
          unawaited(stopChild(143));
        });
      }

      await _runPubGet(projectDirectory.path);
      final packageName = _readPackageName(pubspecFile);
      final entrypointPath = p.join(
        projectDirectory.path,
        entrypointScriptPath,
      );
      final bootstrapper = FastBootstrapper(
        workspace: false,
        compileAot: false,
      );
      final packageConfigUri = Uri.file(
        p.join(projectDirectory.path, '.dart_tool', 'package_config.json'),
      ).toString();
      final buildProcessStateArg = base64.encode(
        utf8.encode(jsonEncode({'packageConfigUri': packageConfigUri})),
      );

      while (true) {
        await FastBootstrapGenerator().generate(
          projectDirectory: projectDirectory.path,
          outputPath: entrypointPath,
          internalLibraryImport: _internalRunnerImport(
            request.internalPackageRootPath,
          ),
          upstreamCommit: upstreamMarker,
        );
        final compileResult = await _withWorkingDirectory(
          projectDirectory.path,
          bootstrapper.ensureCompiled,
        );
        if (!compileResult.succeeded) {
          stderr.writeln(
            'fast_build_runner: failed to compile generated entrypoint.',
          );
          stderr.writeln(compileResult.messages ?? '');
          return 1;
        }

        childProcess = await Process.start(Platform.resolvedExecutable, [
          'run',
          p.join(projectDirectory.path, bootstrapper.entrypointExecutablePath),
          '--mode=live-watch',
          '--project-dir=${projectDirectory.path}',
          '--package-name=$packageName',
          '--entrypoint-script=$entrypointPath',
          '--settle-build-delay-ms=${request.settleBuildDelayMs}',
          '--trust-build-script-freshness=${request.trustBuildScriptFreshness}',
          '--delete-conflicting-outputs=${request.deleteConflictingOutputs}',
          '--build-process-state-base64=$buildProcessStateArg',
        ], workingDirectory: projectDirectory.path);

        unawaited(stdout.addStream(childProcess.stdout));
        unawaited(stderr.addStream(childProcess.stderr));

        final exitCode = await Future.any<int>([
          childProcess.exitCode,
          stopCompleter.future,
        ]);
        if (stopCompleter.isCompleted) {
          return exitCode;
        }
        childProcess = null;

        if (exitCode == _liveRestartExitCode) {
          stdout.writeln(
            'fast_build_runner: build script changed, refreshing watch runtime...',
          );
          await _runPubGet(projectDirectory.path);
          continue;
        }
        return exitCode;
      }
    } finally {
      await sigintSubscription?.cancel();
      await sigtermSubscription?.cancel();
      await overridesManager.restore();
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

  Future<void> _runPubGet(String projectDirectory) async {
    final pubspec = File(p.join(projectDirectory, 'pubspec.yaml'));
    final isFlutterProject = _isFlutterProject(pubspec);
    final command = await _pubGetCommand(isFlutterProject);
    final result = await Process.run(
      command.executable,
      command.arguments,
      workingDirectory: projectDirectory,
    );
    if (result.exitCode != 0) {
      throw StateError(
        '${command.displayName} failed in $projectDirectory\n'
        'stdout:\n${result.stdout}\n'
        'stderr:\n${result.stderr}',
      );
    }
  }

  bool _isFlutterProject(File pubspecFile) {
    final yaml = loadYaml(pubspecFile.readAsStringSync()) as YamlMap;
    final dependencies = yaml['dependencies'];
    if (dependencies is! YamlMap) {
      return false;
    }
    final flutter = dependencies['flutter'];
    return flutter is YamlMap && flutter['sdk'] == 'flutter';
  }

  Future<_PubCommand> _pubGetCommand(bool isFlutterProject) async {
    if (!isFlutterProject) {
      return _PubCommand(
        executable: Platform.resolvedExecutable,
        arguments: const ['pub', 'get'],
        displayName: 'dart pub get',
      );
    }

    final hasFvm = await _commandExists('fvm');
    if (hasFvm) {
      return const _PubCommand(
        executable: 'fvm',
        arguments: ['flutter', 'pub', 'get'],
        displayName: 'fvm flutter pub get',
      );
    }

    return const _PubCommand(
      executable: 'flutter',
      arguments: ['pub', 'get'],
      displayName: 'flutter pub get',
    );
  }

  Future<bool> _commandExists(String executable) async {
    final result = await Process.run('which', [executable]);
    return result.exitCode == 0;
  }

  bool _hasBuildRunnerDependency(File pubspecFile) {
    final yaml = loadYaml(pubspecFile.readAsStringSync()) as YamlMap;
    final dependencies = yaml['dependencies'];
    final devDependencies = yaml['dev_dependencies'];
    return _yamlContainsBuildRunner(dependencies) ||
        _yamlContainsBuildRunner(devDependencies);
  }

  bool _yamlContainsBuildRunner(Object? yamlSection) =>
      yamlSection is YamlMap && yamlSection.containsKey('build_runner');

  String _readPackageName(File pubspecFile) {
    final yaml = loadYaml(pubspecFile.readAsStringSync()) as YamlMap;
    final name = yaml['name'];
    if (name is! String || name.isEmpty) {
      throw StateError('Project pubspec is missing a valid package name.');
    }
    return name;
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

  Future<String> _resolveUpstreamMarker(String upstreamDir) async {
    if (!Directory(upstreamDir).existsSync()) {
      return hostedBuildRunnerMarker;
    }
    final result = await Process.run('git', [
      '-C',
      upstreamDir,
      'rev-parse',
      'HEAD',
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'Unable to read git commit in $upstreamDir: ${result.stderr}',
      );
    }
    return (result.stdout as String).trim();
  }

  Map<String, Object?> _overrideEntries({
    required String repoRoot,
    required bool hasResearchCheckout,
  }) {
    if (hasResearchCheckout) {
      return <String, Object?>{
        'build': <String, Object?>{
          'path': p.join(repoRoot, 'research', 'dart-build', 'build'),
        },
        'build_config': <String, Object?>{
          'path': p.join(repoRoot, 'research', 'dart-build', 'build_config'),
        },
        'build_daemon': <String, Object?>{
          'path': p.join(repoRoot, 'research', 'dart-build', 'build_daemon'),
        },
        'build_runner': <String, Object?>{
          'path': p.join(repoRoot, 'research', 'dart-build', 'build_runner'),
        },
      };
    }

    return <String, Object?>{
      'build': '^4.0.5',
      'build_runner': hostedBuildRunnerConstraint,
    };
  }
}

class _ProjectPubspecOverridesManager {
  final String projectDirectoryPath;

  File get _overridesFile =>
      File(p.join(projectDirectoryPath, 'pubspec_overrides.yaml'));

  String? _originalContents;
  bool _hadOriginalFile = false;

  _ProjectPubspecOverridesManager({required this.projectDirectoryPath});

  Future<void> apply(Map<String, Object?> overrideEntries) async {
    final file = _overridesFile;
    _hadOriginalFile = file.existsSync();
    _originalContents = _hadOriginalFile ? file.readAsStringSync() : null;
    if (_originalContents != null &&
        _originalContents!.startsWith(_generatedOverridesMarker)) {
      _hadOriginalFile = false;
      _originalContents = null;
    }
    final existing = _hadOriginalFile
        ? _parseYamlToMap(_originalContents!)
        : <String, Object?>{};
    final dependencyOverrides =
        (existing['dependency_overrides'] as Map<String, Object?>?) ??
        <String, Object?>{};
    dependencyOverrides.addAll(overrideEntries);
    existing['dependency_overrides'] = dependencyOverrides;
    final contents = StringBuffer()
      ..writeln(_generatedOverridesMarker)
      ..write(_serializeYaml(existing));
    file.writeAsStringSync(contents.toString());
  }

  Future<void> restore() async {
    if (_hadOriginalFile) {
      _overridesFile.writeAsStringSync(_originalContents!);
      return;
    }
    if (_overridesFile.existsSync()) {
      await _overridesFile.delete();
    }
  }

  Map<String, Object?> _parseYamlToMap(String source) {
    final loaded = loadYaml(source);
    if (loaded is! YamlMap) {
      return <String, Object?>{};
    }
    return _convertYamlMap(loaded);
  }

  Map<String, Object?> _convertYamlMap(YamlMap map) {
    final result = <String, Object?>{};
    for (final entry in map.entries) {
      result['${entry.key}'] = _convertYamlValue(entry.value);
    }
    return result;
  }

  Object? _convertYamlValue(Object? value) {
    if (value is YamlMap) {
      return _convertYamlMap(value);
    }
    if (value is YamlList) {
      return value.map(_convertYamlValue).toList();
    }
    return value;
  }

  String _serializeYaml(Object? value, {int indent = 0}) {
    if (value is Map<String, Object?>) {
      final buffer = StringBuffer();
      for (final entry in value.entries) {
        final nested = entry.value;
        if (nested is Map<String, Object?>) {
          buffer.writeln('${'  ' * indent}${entry.key}:');
          buffer.write(_serializeYaml(nested, indent: indent + 1));
        } else if (nested is List) {
          buffer.writeln('${'  ' * indent}${entry.key}:');
          buffer.write(_serializeYaml(nested, indent: indent + 1));
        } else {
          buffer.writeln(
            '${'  ' * indent}${entry.key}: ${_serializeScalar(nested)}',
          );
        }
      }
      return buffer.toString();
    }

    if (value is List) {
      final buffer = StringBuffer();
      for (final item in value) {
        if (item is Map<String, Object?> || item is List) {
          buffer.writeln('${'  ' * indent}-');
          buffer.write(_serializeYaml(item, indent: indent + 1));
        } else {
          buffer.writeln('${'  ' * indent}- ${_serializeScalar(item)}');
        }
      }
      return buffer.toString();
    }

    return '${'  ' * indent}${_serializeScalar(value)}\n';
  }

  String _serializeScalar(Object? value) {
    if (value == null) {
      return 'null';
    }
    if (value is num || value is bool) {
      return '$value';
    }
    final stringValue = '$value';
    if (stringValue.contains(': ') ||
        stringValue.contains('#') ||
        stringValue.contains('{') ||
        stringValue.contains('[') ||
        stringValue.contains('"') ||
        stringValue.contains("'") ||
        stringValue.trim() != stringValue) {
      return jsonEncode(stringValue);
    }
    return stringValue;
  }
}

class _PubCommand {
  final String executable;
  final List<String> arguments;
  final String displayName;

  const _PubCommand({
    required this.executable,
    required this.arguments,
    required this.displayName,
  });
}
