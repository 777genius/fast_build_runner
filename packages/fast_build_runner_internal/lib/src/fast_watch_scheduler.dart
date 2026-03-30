// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:build/build.dart';
import 'package:watcher/watcher.dart';

import 'watch_update_merger.dart';

/// Serializes incremental builds so only one build runs at a time.
///
/// New update batches that arrive while a build is in flight are merged into a
/// single pending batch and processed immediately after the current build
/// completes.
class FastWatchScheduledBuild<T> {
  final Map<AssetId, ChangeType> updates;
  final int elapsedMilliseconds;
  final T result;

  const FastWatchScheduledBuild({
    required this.updates,
    required this.elapsedMilliseconds,
    required this.result,
  });
}

class FastWatchScheduler<T> {
  final Future<T> Function(
    Map<AssetId, ChangeType> updates, {
    required bool skipBuildScriptFreshnessCheck,
  })
  _onBuild;
  final Duration _postBuildSettleDelay;
  final StreamController<FastWatchScheduledBuild<T>> _resultsController =
      StreamController.broadcast();

  Map<AssetId, ChangeType> _pendingUpdates = <AssetId, ChangeType>{};
  bool _hasPendingBuild = false;
  bool _pendingSkipBuildScriptFreshnessCheck = true;
  Future<void>? _pumpFuture;
  Completer<void> _idleCompleter = Completer<void>()..complete();
  bool _closed = false;
  DateTime? _lastEnqueueAt;

  FastWatchScheduler({
    required Future<T> Function(
      Map<AssetId, ChangeType> updates, {
      required bool skipBuildScriptFreshnessCheck,
    })
    onBuild,
    Duration postBuildSettleDelay = Duration.zero,
  }) : _onBuild = onBuild,
       _postBuildSettleDelay = postBuildSettleDelay;

  Stream<FastWatchScheduledBuild<T>> get results => _resultsController.stream;

  bool get isBusy => _pumpFuture != null;

  Future<void> enqueue(
    Map<AssetId, ChangeType> updates, {
    required bool skipBuildScriptFreshnessCheck,
  }) {
    if (_closed) {
      throw StateError('FastWatchScheduler is closed.');
    }
    final shouldScheduleBuild =
        updates.isNotEmpty || !skipBuildScriptFreshnessCheck;
    if (!shouldScheduleBuild) {
      return waitForIdle();
    }
    if (!_hasPendingBuild) {
      _pendingSkipBuildScriptFreshnessCheck = skipBuildScriptFreshnessCheck;
    } else {
      _pendingSkipBuildScriptFreshnessCheck =
          _pendingSkipBuildScriptFreshnessCheck &&
          skipBuildScriptFreshnessCheck;
    }
    _hasPendingBuild = true;
    if (updates.isNotEmpty) {
      _pendingUpdates = mergeAssetChangeMaps([_pendingUpdates, updates]);
    }
    _lastEnqueueAt = DateTime.now();
    if (_idleCompleter.isCompleted) {
      _idleCompleter = Completer<void>();
    }
    _pumpFuture ??= _pump();
    return waitForIdle();
  }

  Future<void> waitForIdle() => _idleCompleter.future;

  Future<void> close() async {
    _closed = true;
    await _pumpFuture;
    if (!_idleCompleter.isCompleted) {
      _idleCompleter.complete();
    }
    await _resultsController.close();
  }

  Future<void> _pump() async {
    try {
      while (_hasPendingBuild) {
        final updates = _pendingUpdates;
        final skipBuildScriptFreshnessCheck =
            _pendingSkipBuildScriptFreshnessCheck;
        _pendingUpdates = <AssetId, ChangeType>{};
        _pendingSkipBuildScriptFreshnessCheck = true;
        _hasPendingBuild = false;
        final stopwatch = Stopwatch()..start();
        final result = await _onBuild(
          updates,
          skipBuildScriptFreshnessCheck: skipBuildScriptFreshnessCheck,
        );
        stopwatch.stop();
        _resultsController.add(
          FastWatchScheduledBuild(
            updates: Map<AssetId, ChangeType>.from(updates),
            elapsedMilliseconds: stopwatch.elapsedMilliseconds,
            result: result,
          ),
        );
        if (_hasPendingBuild) {
          await _waitForPostBuildSettleWindow();
        }
      }
    } finally {
      _pumpFuture = null;
      if (!_idleCompleter.isCompleted) {
        _idleCompleter.complete();
      }
    }
  }

  Future<void> _waitForPostBuildSettleWindow() async {
    if (_postBuildSettleDelay <= Duration.zero) {
      return;
    }
    final lastEnqueueAt = _lastEnqueueAt;
    if (lastEnqueueAt == null) {
      return;
    }
    final elapsedSinceLastEnqueue = DateTime.now().difference(lastEnqueueAt);
    final remainingDelay = _postBuildSettleDelay - elapsedSinceLastEnqueue;
    if (remainingDelay > Duration.zero) {
      await Future<void>.delayed(remainingDelay);
    }
  }
}
