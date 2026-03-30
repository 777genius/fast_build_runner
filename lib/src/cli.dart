import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:fast_build_runner_internal/fast_build_runner_internal.dart';

class FastBuildRunnerCli {
  Future<int> run(List<String> args) async {
    if (args.isEmpty) {
      _printUsage();
      return 64;
    }

    final command = args.first;
    final rest = args.sublist(1);
    switch (command) {
      case 'spike-bootstrap':
        return _runSpikeBootstrap(rest);
      case 'spike-watch':
        return _runSpikeWatch(rest);
      case 'help':
      case '--help':
      case '-h':
        _printUsage();
        return 0;
      default:
        stderr.writeln('Unknown command: $command');
        _printUsage();
        return 64;
    }
  }

  Future<int> _runSpikeBootstrap(List<String> args) async {
    final parser = ArgParser()
      ..addOption(
        'fixture',
        defaultsTo: 'fixtures/json_serializable_fixture',
        help: 'Path to the fixture template relative to the repo root.',
      )
      ..addOption(
        'work-dir',
        defaultsTo: '.dart_tool/fast_build_runner/spike',
        help: 'Directory used for copied fixture runs.',
      )
      ..addFlag(
        'keep-run-dir',
        negatable: false,
        help: 'Keep the copied fixture directory after execution.',
      )
      ..addFlag(
        'mutate-build-script-before-incremental',
        negatable: false,
        help:
            'For verification: mutate the generated build script before the second run and expect buildScriptChanged.',
      );

    final parsed = parser.parse(args);
    final repoRoot = _resolveRepoRoot();
    final request = FastBootstrapSpikeRequest(
      repoRoot: repoRoot.path,
      fixtureTemplatePath: _resolveFromRoot(
        repoRoot,
        parsed['fixture'] as String,
      ),
      workDirectoryPath: _resolveFromRoot(
        repoRoot,
        parsed['work-dir'] as String,
      ),
      keepRunDirectory: parsed['keep-run-dir'] as bool,
      mutateBuildScriptBeforeIncremental:
          parsed['mutate-build-script-before-incremental'] as bool,
    );
    final result = await FastBootstrapSpikeRunner().run(request);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
    return result.exitCode;
  }

  Future<int> _runSpikeWatch(List<String> args) async {
    final parser = ArgParser()
      ..addOption(
        'fixture',
        defaultsTo: 'fixtures/json_serializable_fixture',
        help: 'Path to the fixture template relative to the repo root.',
      )
      ..addOption(
        'work-dir',
        defaultsTo: '.dart_tool/fast_build_runner/watch_alpha',
        help: 'Directory used for copied watch-alpha fixture runs.',
      )
      ..addFlag(
        'keep-run-dir',
        negatable: false,
        help: 'Keep the copied fixture directory after execution.',
      )
      ..addFlag(
        'mutate-build-script-before-incremental',
        negatable: false,
        help:
            'For verification: mutate the generated build script during watch alpha and expect buildScriptChanged.',
      )
      ..addOption(
        'source-engine',
        defaultsTo: 'dart',
        allowed: const ['dart', 'rust'],
        help: 'Filesystem event source used by watch alpha.',
      );

    final parsed = parser.parse(args);
    final repoRoot = _resolveRepoRoot();
    final request = FastWatchAlphaRequest(
      repoRoot: repoRoot.path,
      fixtureTemplatePath: _resolveFromRoot(
        repoRoot,
        parsed['fixture'] as String,
      ),
      workDirectoryPath: _resolveFromRoot(
        repoRoot,
        parsed['work-dir'] as String,
      ),
      keepRunDirectory: parsed['keep-run-dir'] as bool,
      sourceEngine: parsed['source-engine'] as String,
      mutateBuildScriptBeforeIncremental:
          parsed['mutate-build-script-before-incremental'] as bool,
    );
    final result = await FastWatchAlphaRunner().run(request);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
    return result.exitCode;
  }

  Directory _resolveRepoRoot() {
    final scriptFile = File.fromUri(Platform.script);
    return scriptFile.parent.parent;
  }

  String _resolveFromRoot(Directory root, String relativeOrAbsolute) {
    final path = relativeOrAbsolute;
    if (path.startsWith('/')) {
      return path;
    }
    return '${root.path}/$path';
  }

  void _printUsage() {
    stdout.writeln('Usage: fast_build_runner <command>');
    stdout.writeln('');
    stdout.writeln('Commands:');
    stdout.writeln(
      '  spike-bootstrap   Run the bootstrap seam proof against the bundled fixture.',
    );
    stdout.writeln(
      '  spike-watch       Run a finite watch-alpha proof against the bundled fixture.',
    );
  }
}
