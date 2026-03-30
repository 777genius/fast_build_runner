// ignore_for_file: implementation_imports

import 'package:build/build.dart';
import 'package:watcher/watcher.dart';

Map<AssetId, ChangeType> mergeAssetChangeMaps(
  Iterable<Map<AssetId, ChangeType>> changes,
) {
  final changeMap = <AssetId, ChangeType>{};
  for (final batch in changes) {
    for (final entry in batch.entries) {
      final id = entry.key;
      final nextChangeType = entry.value;
      final originalChangeType = changeMap[id];
      if (originalChangeType != null) {
        switch (originalChangeType) {
          case ChangeType.ADD:
            if (nextChangeType == ChangeType.REMOVE) {
              changeMap.remove(id);
            }
            break;
          case ChangeType.REMOVE:
            if (nextChangeType == ChangeType.ADD) {
              changeMap[id] = ChangeType.MODIFY;
            } else if (nextChangeType == ChangeType.MODIFY) {
              throw StateError(
                'Internal merge error: got REMOVE followed by MODIFY for $id.',
              );
            }
            break;
          case ChangeType.MODIFY:
            if (nextChangeType == ChangeType.REMOVE) {
              changeMap[id] = nextChangeType;
            } else if (nextChangeType == ChangeType.ADD) {
              throw StateError(
                'Internal merge error: got MODIFY followed by ADD for $id.',
              );
            }
            break;
        }
      } else {
        changeMap[id] = nextChangeType;
      }
    }
  }
  return changeMap;
}
