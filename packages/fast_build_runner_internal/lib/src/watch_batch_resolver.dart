// ignore_for_file: implementation_imports

import 'package:build/build.dart';
import 'package:watcher/watcher.dart';

class WatchBatchResolution {
  final Map<AssetId, ChangeType> updates;
  final bool usedResync;
  final String? warning;

  const WatchBatchResolution({
    required this.updates,
    required this.usedResync,
    required this.warning,
  });
}

Future<WatchBatchResolution> resolveWatchBatch({
  required Map<AssetId, ChangeType> watcherUpdates,
  required bool watcherBatchWasEmpty,
  required AssetId expectedSourceAssetId,
  required Future<Map<AssetId, ChangeType>> Function() collectSourceUpdates,
}) async {
  final suspicionReason = _suspicionReason(
    watcherUpdates: watcherUpdates,
    watcherBatchWasEmpty: watcherBatchWasEmpty,
    expectedSourceAssetId: expectedSourceAssetId,
  );
  if (suspicionReason == null) {
    return WatchBatchResolution(
      updates: watcherUpdates,
      usedResync: false,
      warning: null,
    );
  }

  final filesystemUpdates = await collectSourceUpdates();
  if (filesystemUpdates.isEmpty) {
    return WatchBatchResolution(
      updates: watcherUpdates,
      usedResync: false,
      warning:
          'Watch batch looked suspicious: $suspicionReason. Filesystem resync found no actionable changes, so the original watcher batch was kept.',
    );
  }

  return WatchBatchResolution(
    updates: filesystemUpdates,
    usedResync: true,
    warning:
        'Watch batch looked suspicious: $suspicionReason. Replaced watcher updates with filesystem resync updates.',
  );
}

String? _suspicionReason({
  required Map<AssetId, ChangeType> watcherUpdates,
  required bool watcherBatchWasEmpty,
  required AssetId expectedSourceAssetId,
}) {
  if (watcherBatchWasEmpty) {
    return 'watcher batch was empty';
  }
  if (watcherUpdates.isEmpty) {
    return 'watcher batch did not resolve to any tracked asset updates';
  }
  final sourceChange = watcherUpdates[expectedSourceAssetId];
  if (sourceChange == null) {
    return 'watcher batch did not include the expected source asset $expectedSourceAssetId';
  }
  if (sourceChange != ChangeType.MODIFY) {
    return 'watcher batch reported $sourceChange for expected modified source asset $expectedSourceAssetId';
  }
  return null;
}
