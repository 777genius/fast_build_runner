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
      case 'watch':
        return _runWatch(rest);
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
    final processArgs = <String>['run', 'build_runner', 'build', ...args];

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
    final repoRoot = await _resolveRepoRoot();
    final internalPackageRoot =
        _resolvePackageRootFromPackageConfig('fast_build_runner_internal') ??
        Directory('${repoRoot.path}/packages/fast_build_runner_internal');
    final request = FastBootstrapSpikeRequest(
      repoRoot: repoRoot.path,
      internalPackageRootPath: internalPackageRoot.path,
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

  Future<int> _runWatch(List<String> args) async {
    final parser = ArgParser()
      ..addOption(
        'project-dir',
        defaultsTo: '.',
        help: 'Project directory to watch. Defaults to the current directory.',
      )
      ..addOption(
        'settle-build-delay-ms',
        defaultsTo: '150',
        help:
            'Post-build settle window for coalescing another filesystem batch before the next rebuild.',
      )
      ..addFlag(
        'trust-build-script-freshness',
        defaultsTo: true,
        help:
            'Fast path: skip incremental build-script freshness checks unless relevant build inputs changed.',
      )
      ..addFlag(
        'delete-conflicting-outputs',
        negatable: false,
        help:
            'Compatibility flag for build_runner-style usage. The watch runtime clears conflicting outputs during bootstrap.',
      );

    final parsed = parser.parse(args);
    final repoRoot = await _resolveRepoRoot();
    final internalPackageRoot =
        _resolvePackageRootFromPackageConfig('fast_build_runner_internal') ??
        Directory('${repoRoot.path}/packages/fast_build_runner_internal');
    return FastProjectWatchRunner().run(
      FastProjectWatchRequest(
        repoRoot: repoRoot.path,
        internalPackageRootPath: internalPackageRoot.path,
        projectDirectoryPath: _resolveFromRoot(
          Directory.current.absolute,
          parsed['project-dir'] as String,
        ),
        deleteConflictingOutputs: parsed['delete-conflicting-outputs'] as bool,
        settleBuildDelayMs: int.parse(
          parsed['settle-build-delay-ms'] as String,
        ),
        trustBuildScriptFreshness:
            parsed['trust-build-script-freshness'] as bool,
      ),
    );
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
      )
      ..addFlag(
        'delete-conflicting-outputs',
        negatable: false,
        help:
            'Compatibility flag for build_runner-style examples. The watch runtime already clears conflicting outputs during bootstrap.',
      );

    final parsed = parser.parse(args);
    final repoRoot = await _resolveRepoRoot();
    final internalPackageRoot =
        _resolvePackageRootFromPackageConfig('fast_build_runner_internal') ??
        Directory('${repoRoot.path}/packages/fast_build_runner_internal');
    final request = FastWatchAlphaRequest(
      repoRoot: repoRoot.path,
      internalPackageRootPath: internalPackageRoot.path,
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
      deleteConflictingOutputs: parsed['delete-conflicting-outputs'] as bool,
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
    final repoRoot = await _resolveRepoRoot();
    final internalPackageRoot =
        _resolvePackageRootFromPackageConfig('fast_build_runner_internal') ??
        Directory('${repoRoot.path}/packages/fast_build_runner_internal');
    final request = FastWatchBenchmarkRequest(
      repoRoot: repoRoot.path,
      internalPackageRootPath: internalPackageRoot.path,
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

  Future<Directory> _resolveRepoRoot() async {
    final configuredRoot = _resolveRepoRootFromPackageConfig();
    if (configuredRoot != null) {
      return configuredRoot;
    }

    final seen = <String>{};
    final searchRoots = <Directory>[
      File.fromUri(Platform.script).parent,
      File.fromUri(Platform.script).parent.parent,
      Directory.current,
    ];

    for (final root in searchRoots) {
      var current = root.absolute;
      while (seen.add(current.path)) {
        if (_looksLikeFastBuildRunnerRoot(current)) {
          return current;
        }
        final parent = current.parent;
        if (parent.path == current.path) {
          break;
        }
        current = parent;
      }
    }

    throw StateError(
      'Unable to locate the fast_build_runner package root from ${Platform.script}.',
    );
  }

  Directory? _resolveRepoRootFromPackageConfig() {
    return _resolvePackageRootFromPackageConfig('fast_build_runner');
  }

  Directory? _resolvePackageRootFromPackageConfig(String packageName) {
    final scriptDirectory = File.fromUri(Platform.script).parent.absolute;
    var current = scriptDirectory;

    while (true) {
      final packageConfigFile = File(
        '${current.path}/.dart_tool/package_config.json',
      );
      if (packageConfigFile.existsSync()) {
        final packageRoot = _readPackageRootFromPackageConfig(
          packageConfigFile,
          packageName,
        );
        if (packageRoot != null) {
          return packageRoot;
        }
      }

      final parent = current.parent;
      if (parent.path == current.path) {
        return null;
      }
      current = parent;
    }
  }

  Directory? _readPackageRootFromPackageConfig(
    File packageConfigFile,
    String packageName,
  ) {
    final decoded = jsonDecode(packageConfigFile.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      return null;
    }

    final packages = decoded['packages'];
    if (packages is! List) {
      return null;
    }

    for (final package in packages) {
      if (package is! Map) {
        continue;
      }
      if (package['name'] != packageName) {
        continue;
      }

      final rootUriValue = package['rootUri'];
      if (rootUriValue is! String || rootUriValue.isEmpty) {
        return null;
      }

      final rootUri = Uri.parse(rootUriValue);
      final rootDirectory = rootUri.isScheme('file')
          ? Directory.fromUri(rootUri)
          : Directory.fromUri(packageConfigFile.parent.uri.resolveUri(rootUri));
      if (_looksLikeFastBuildRunnerRoot(rootDirectory)) {
        return rootDirectory;
      }
      return rootDirectory;
    }

    return null;
  }

  bool _looksLikeFastBuildRunnerRoot(Directory directory) {
    final pubspec = File('${directory.path}/pubspec.yaml');
    if (!pubspec.existsSync()) {
      return false;
    }

    final pubspecContents = pubspec.readAsStringSync();
    if (!pubspecContents.contains(
      RegExp(r'^name:\s*fast_build_runner\s*$', multiLine: true),
    )) {
      return false;
    }

    return File('${directory.path}/bin/fast_build_runner.dart').existsSync();
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
      '  watch             Run a long-lived fast watch loop for the current project.',
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
