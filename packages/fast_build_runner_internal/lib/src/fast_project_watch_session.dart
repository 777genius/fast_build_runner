// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:io';

import 'package:build/build.dart';
import 'package:build_runner/src/internal.dart';
import 'package:built_collection/built_collection.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'fast_build_plan.dart';
import 'fast_build_run_profile.dart';
import 'fast_build_series.dart';
import 'fast_watch_scheduler.dart';

const _liveWatchDebounceMs = 250;
const _liveRestartExitCode = 75;

class FastProjectWatchSession {
  final BuilderFactories builderFactories;
  final String upstreamCommit;

  const FastProjectWatchSession({
    required this.builderFactories,
    required this.upstreamCommit,
  });

  Future<int> run({
    required String packageName,
    required String generatedEntrypointPath,
    required String runDirectory,
    required bool trustBuildScriptFreshness,
    required bool deleteConflictingOutputs,
    required int settleBuildDelayMs,
  }) async {
    final buildPlan = await FastBuildPlan.load(
      builderFactories: builderFactories,
      buildOptions: BuildOptions(
        buildDirs: BuiltSet<BuildDirectory>(),
        builderConfigOverrides: BuiltMap<String, BuiltMap<String, Object?>>(),
        buildFilters: BuiltSet<BuildFilter>(),
        configKey: null,
        dartAotPerf: false,
        enableExperiments: BuiltList<String>(),
        enableLowResourcesMode: false,
        forceAot: false,
        forceJit: false,
        isReleaseBuild: false,
        logPerformanceDir: null,
        outputSymlinksOnly: false,
        trackPerformance: true,
        verbose: false,
        verboseDurations: false,
        workspace: false,
      ),
      testingOverrides: const TestingOverrides(),
      recentlyBootstrapped: true,
    );

    if (deleteConflictingOutputs) {
      stdout.writeln(
        'fast_build_runner: clearing conflicting outputs before starting watch.',
      );
    }
    await buildPlan.deleteFilesAndFolders();
    if (buildPlan.restartIsNeeded) {
      stdout.writeln(
        'fast_build_runner: build script restart is needed before watch could start.',
      );
      return _liveRestartExitCode;
    }

    final buildSeries = FastBuildSeries(buildPlan);
    final compileDependencyPaths = buildPlan.bootstrapper
        .compileDependencyPathsWithinRoot(Directory.current.path);
    final scheduler = FastWatchScheduler(
      onBuild: (updates, {required skipBuildScriptFreshnessCheck}) =>
          buildSeries.run(
            updates,
            recentlyBootstrapped: false,
            skipBuildScriptFreshnessCheck: skipBuildScriptFreshnessCheck,
          ),
      postBuildSettleDelay: Duration(milliseconds: settleBuildDelayMs),
    );
    final directoryWatcher = DirectoryWatcher(Directory.current.path);
    final done = Completer<int>();
    final pendingUpdates = <AssetId, ChangeType>{};
    final pendingChangedPaths = <String>{};
    final pendingObservedEvents = <String>[];
    Timer? debounceTimer;
    StreamSubscription<WatchEvent>? watcherSubscription;
    StreamSubscription<FastWatchScheduledBuild<FastBuildRunOutcome>>?
    resultSubscription;
    var rebuildCount = 0;

    Future<void> flushPendingBatch() async {
      if (pendingObservedEvents.isEmpty && pendingChangedPaths.isEmpty) {
        return;
      }

      final observedEvents = List<String>.from(pendingObservedEvents);
      final changedPaths = List<String>.from(pendingChangedPaths);
      final updates = Map<AssetId, ChangeType>.from(pendingUpdates);
      pendingObservedEvents.clear();
      pendingChangedPaths.clear();
      pendingUpdates.clear();

      final skipBuildScriptFreshnessCheck =
          trustBuildScriptFreshness &&
          !_requiresBuildScriptFreshnessCheck(
            changedPaths: changedPaths,
            compileDependencyPaths: compileDependencyPaths,
            generatedEntrypointPath: generatedEntrypointPath,
          );

      final changeSummary = updates.isEmpty
          ? '0 merged asset updates'
          : '${updates.length} merged asset update(s)';
      stdout.writeln(
        'fast_build_runner: observed ${observedEvents.length} event(s), scheduling $changeSummary.',
      );

      unawaited(
        scheduler.enqueue(
          updates,
          skipBuildScriptFreshnessCheck: skipBuildScriptFreshnessCheck,
        ),
      );
    }

    try {
      final initialStopwatch = Stopwatch()..start();
      final initialBuild = await buildSeries.run(
        {},
        recentlyBootstrapped: true,
      );
      initialStopwatch.stop();
      _printBuildOutcome(
        label: 'initial build',
        elapsedMilliseconds: initialStopwatch.elapsedMilliseconds,
        outcome: initialBuild,
      );
      if (_isBuildScriptChanged(initialBuild.result)) {
        return _liveRestartExitCode;
      }

      resultSubscription = scheduler.results.listen((scheduledBuild) {
        rebuildCount++;
        _printBuildOutcome(
          label: 'rebuild #$rebuildCount',
          elapsedMilliseconds: scheduledBuild.elapsedMilliseconds,
          outcome: scheduledBuild.result,
        );
        if (_isBuildScriptChanged(scheduledBuild.result.result) &&
            !done.isCompleted) {
          done.complete(_liveRestartExitCode);
        }
      });

      watcherSubscription = directoryWatcher.events.listen(
        (event) {
          final relativePath = _relativePath(event.path);
          if (_shouldIgnoreRelativePath(relativePath)) {
            return;
          }
          final assetId = AssetId(packageName, relativePath!);
          if (buildSeries.isGeneratedAsset(assetId)) {
            return;
          }

          pendingObservedEvents.add('${event.type}:$relativePath');
          pendingChangedPaths.add(event.path);
          pendingUpdates[assetId] = event.type;
          debounceTimer?.cancel();
          debounceTimer = Timer(
            const Duration(milliseconds: _liveWatchDebounceMs),
            () {
              unawaited(flushPendingBatch());
            },
          );
        },
        onError: (Object error, StackTrace stackTrace) {
          stderr.writeln('fast_build_runner: watch stream error: $error');
          if (!done.isCompleted) {
            done.complete(1);
          }
        },
      );
      await directoryWatcher.ready;
      stdout.writeln(
        'fast_build_runner: watching ${Directory.current.path} with upstream $upstreamCommit.',
      );
      stdout.writeln('fast_build_runner: press Ctrl+C to stop.');

      return await done.future;
    } finally {
      debounceTimer?.cancel();
      await watcherSubscription?.cancel();
      await resultSubscription?.cancel();
      await scheduler.close();
      await buildSeries.close();
    }
  }

  bool _shouldIgnoreRelativePath(String? relativePath) {
    if (relativePath == null) {
      return true;
    }
    if (relativePath.startsWith('build/')) {
      return true;
    }
    if (relativePath.startsWith('.dart_tool/fast_build_runner/')) {
      return true;
    }
    if (relativePath.startsWith('.dart_tool/build/generated/')) {
      return true;
    }
    if (relativePath == 'pubspec.lock') {
      return true;
    }
    return false;
  }

  String? _relativePath(String path) {
    final absolutePath = p.isAbsolute(path)
        ? path
        : p.join(Directory.current.path, path);
    if (!p.isWithin(Directory.current.path, absolutePath) &&
        !p.equals(Directory.current.path, absolutePath)) {
      return null;
    }
    return p.relative(absolutePath, from: Directory.current.path);
  }

  bool _requiresBuildScriptFreshnessCheck({
    required List<String> changedPaths,
    required Set<String> compileDependencyPaths,
    required String generatedEntrypointPath,
  }) {
    if (changedPaths.isEmpty) {
      return false;
    }

    final normalizedEntrypointPath = File(
      generatedEntrypointPath,
    ).absolute.path;
    for (final changedPath in changedPaths) {
      final absolutePath = File(changedPath).absolute.path;
      final relativePath = _relativePath(absolutePath);
      if (absolutePath == normalizedEntrypointPath) {
        return true;
      }
      if (relativePath == 'build.yaml' || relativePath == 'pubspec.yaml') {
        return true;
      }
      if (compileDependencyPaths.contains(absolutePath)) {
        return true;
      }
    }
    return false;
  }

  void _printBuildOutcome({
    required String label,
    required int elapsedMilliseconds,
    required FastBuildRunOutcome outcome,
  }) {
    final result = outcome.result;
    final seconds = (elapsedMilliseconds / 1000).toStringAsFixed(2);
    final outputs = result.outputs.length;
    final errors = result.errors.length;
    final failureType = result.failureType?.toString();
    final summary =
        'fast_build_runner: $label finished in ${seconds}s '
        'with status ${result.status.name} '
        '($outputs output(s), $errors error(s)).';
    stdout.writeln(summary);
    if (failureType != null) {
      stdout.writeln('fast_build_runner: failure type = $failureType');
    }
    for (final error in result.errors) {
      stderr.writeln(error);
    }
  }

  bool _isBuildScriptChanged(BuildResult result) =>
      identical(result.failureType, FailureType.buildScriptChanged);
}
