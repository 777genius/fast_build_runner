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
class FastWatchScheduler<T> {
  final Future<T> Function(Map<AssetId, ChangeType> updates) _onBuild;
  final StreamController<T> _resultsController = StreamController.broadcast();

  Map<AssetId, ChangeType> _pendingUpdates = <AssetId, ChangeType>{};
  Future<void>? _pumpFuture;
  Completer<void> _idleCompleter = Completer<void>()..complete();
  bool _closed = false;

  FastWatchScheduler({required Future<T> Function(Map<AssetId, ChangeType>) onBuild})
    : _onBuild = onBuild;

  Stream<T> get results => _resultsController.stream;

  bool get isBusy => _pumpFuture != null;

  Future<void> enqueue(Map<AssetId, ChangeType> updates) {
    if (_closed) {
      throw StateError('FastWatchScheduler is closed.');
    }
    if (updates.isEmpty) {
      return waitForIdle();
    }
    _pendingUpdates = mergeAssetChangeMaps([_pendingUpdates, updates]);
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
      while (_pendingUpdates.isNotEmpty) {
        final updates = _pendingUpdates;
        _pendingUpdates = <AssetId, ChangeType>{};
        final result = await _onBuild(updates);
        _resultsController.add(result);
      }
    } finally {
      _pumpFuture = null;
      if (!_idleCompleter.isCompleted) {
        _idleCompleter.complete();
      }
    }
  }
}
