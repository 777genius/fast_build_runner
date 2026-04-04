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
      case 'build':
        return _runUpstreamBuild(rest);
      case 'spike-bootstrap':
        return _runSpikeBootstrap(rest);
      case 'spike-watch':
        return _runSpikeWatch(rest);
      case 'benchmark-watch':
        return _runBenchmarkWatch(rest);
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

  Future<int> _runUpstreamBuild(List<String> args) async {
    final processArgs = <String>[
      'run',
      'build_runner',
      'build',
      ...args,
    ];

    try {
      final process = await Process.start(
        Platform.resolvedExecutable,
        processArgs,
        workingDirectory: Directory.current.path,
        mode: ProcessStartMode.inheritStdio,
      );
      return await process.exitCode;
    } on ProcessException catch (error) {
      stderr.writeln(
        'Failed to launch upstream build_runner build: ${error.message}',
      );
      return 1;
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
      ..addOption(
        'mutation-profile',
        help:
            'Optional path to a JSON mutation profile for real-project benchmarking.',
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
        allowed: const ['dart', 'rust', 'upstream'],
        help: 'Filesystem event source used by watch alpha.',
      )
      ..addOption(
        'incremental-cycles',
        defaultsTo: '1',
        help: 'Number of incremental watch batches to execute before exiting.',
      )
      ..addOption(
        'noise-files-per-cycle',
        defaultsTo: '0',
        help: 'How many unrelated noise files to mutate on every watch cycle.',
      )
      ..addFlag(
        'continuous-scheduling',
        negatable: false,
        help:
            'Keep collecting watch batches while a build is in flight and let the scheduler coalesce them.',
      )
      ..addOption(
        'extra-fixture-models',
        defaultsTo: '0',
        help:
            'Generate extra json_serializable models inside the copied fixture to make the benchmark heavier.',
      )
      ..addOption(
        'settle-build-delay-ms',
        defaultsTo: '0',
        help:
            'Optional post-build settle window for coalescing another watch batch before scheduling the next rebuild.',
      )
      ..addFlag(
        'trust-build-script-freshness',
        defaultsTo: true,
        help:
            'Fast path: skip incremental build-script freshness checks after bootstrap unless relevant build script inputs changed.',
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
      mutationProfilePath: parsed['mutation-profile'] == null
          ? null
          : _resolveFromRoot(repoRoot, parsed['mutation-profile'] as String),
      sourceEngine: parsed['source-engine'] as String,
      incrementalCycles: int.parse(parsed['incremental-cycles'] as String),
      noiseFilesPerCycle: int.parse(parsed['noise-files-per-cycle'] as String),
      continuousScheduling: parsed['continuous-scheduling'] as bool,
      extraFixtureModels: int.parse(parsed['extra-fixture-models'] as String),
      settleBuildDelayMs: int.parse(parsed['settle-build-delay-ms'] as String),
      trustBuildScriptFreshness: parsed['trust-build-script-freshness'] as bool,
      mutateBuildScriptBeforeIncremental:
          parsed['mutate-build-script-before-incremental'] as bool,
    );
    final result = await FastWatchAlphaRunner().run(request);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
    return result.exitCode;
  }

  Future<int> _runBenchmarkWatch(List<String> args) async {
    final parser = ArgParser()
      ..addOption(
        'fixture',
        defaultsTo: 'fixtures/json_serializable_fixture',
        help: 'Path to the fixture template relative to the repo root.',
      )
      ..addOption(
        'work-dir',
        defaultsTo: '.dart_tool/fast_build_runner/watch_benchmark',
        help: 'Directory used for benchmark fixture runs.',
      )
      ..addOption(
        'mutation-profile',
        help:
            'Optional path to a JSON mutation profile for real-project benchmarking.',
      )
      ..addFlag(
        'keep-run-dir',
        negatable: false,
        help: 'Keep copied fixture directories after execution.',
      )
      ..addOption(
        'incremental-cycles',
        defaultsTo: '1',
        help: 'Number of incremental cycles per engine.',
      )
      ..addOption(
        'repeats',
        defaultsTo: '1',
        help:
            'How many runs to execute per engine before choosing the median sample.',
      )
      ..addOption(
        'noise-files-per-cycle',
        defaultsTo: '0',
        help: 'How many unrelated noise files to mutate on every watch cycle.',
      )
      ..addFlag(
        'continuous-scheduling',
        negatable: false,
        help:
            'Keep collecting watch batches while a build is in flight and let the scheduler coalesce them.',
      )
      ..addOption(
        'extra-fixture-models',
        defaultsTo: '0',
        help:
            'Generate extra json_serializable models inside the copied fixture to make the benchmark heavier.',
      )
      ..addOption(
        'settle-build-delay-ms',
        defaultsTo: '0',
        help:
            'Optional post-build settle window for coalescing another watch batch before scheduling the next rebuild.',
      )
      ..addFlag(
        'trust-build-script-freshness',
        defaultsTo: true,
        help:
            'Fast path: skip incremental build-script freshness checks after bootstrap unless relevant build script inputs changed.',
      )
      ..addFlag(
        'include-upstream',
        negatable: false,
        help:
            'Also benchmark the upstream build_runner watch loop as a baseline.',
      )
      ..addOption(
        'output',
        defaultsTo: 'json',
        allowed: const ['json', 'summary', 'markdown'],
        help: 'How to print the benchmark result.',
      );

    final parsed = parser.parse(args);
    final repoRoot = _resolveRepoRoot();
    final request = FastWatchBenchmarkRequest(
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
      mutationProfilePath: parsed['mutation-profile'] == null
          ? null
          : _resolveFromRoot(repoRoot, parsed['mutation-profile'] as String),
      incrementalCycles: int.parse(parsed['incremental-cycles'] as String),
      repeats: int.parse(parsed['repeats'] as String),
      noiseFilesPerCycle: int.parse(parsed['noise-files-per-cycle'] as String),
      continuousScheduling: parsed['continuous-scheduling'] as bool,
      extraFixtureModels: int.parse(parsed['extra-fixture-models'] as String),
      settleBuildDelayMs: int.parse(parsed['settle-build-delay-ms'] as String),
      trustBuildScriptFreshness: parsed['trust-build-script-freshness'] as bool,
      includeUpstream: parsed['include-upstream'] as bool,
    );
    final result = await FastWatchBenchmarkRunner().run(request);
    switch (parsed['output'] as String) {
      case 'summary':
        stdout.writeln(result.toSummaryLines().join('\n'));
        break;
      case 'markdown':
        stdout.writeln(result.toMarkdown());
        break;
      case 'json':
      default:
        stdout.writeln(
          const JsonEncoder.withIndent('  ').convert(result.toJson()),
        );
        break;
    }
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
      '  build             Proxy to upstream build_runner build for one-shot builds.',
    );
    stdout.writeln(
      '  spike-bootstrap   Run the bootstrap seam proof against the bundled fixture.',
    );
    stdout.writeln(
      '  spike-watch       Run a finite watch-alpha proof against the bundled fixture.',
    );
    stdout.writeln(
      '  benchmark-watch   Compare dart and rust source engines on the bundled watch fixture.',
    );
  }
}
