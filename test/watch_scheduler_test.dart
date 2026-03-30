import 'dart:async';

import 'package:build/build.dart';
import 'package:fast_build_runner_internal/fast_build_runner_internal.dart';
import 'package:test/test.dart';
import 'package:watcher/watcher.dart';

void main() {
  test(
    'watch scheduler merges pending batches while a build is in flight',
    () async {
      final startedFirstBuild = Completer<void>();
      final releaseFirstBuild = Completer<void>();
      final capturedBatches = <Map<AssetId, ChangeType>>[];
      final scheduledResults =
          <FastWatchScheduledBuild<Map<AssetId, ChangeType>>>[];

      final scheduler = FastWatchScheduler<Map<AssetId, ChangeType>>(
        onBuild: (updates) async {
          capturedBatches.add(Map<AssetId, ChangeType>.from(updates));
          if (capturedBatches.length == 1) {
            startedFirstBuild.complete();
            await releaseFirstBuild.future;
          }
          return updates;
        },
      );
      final subscription = scheduler.results.listen(scheduledResults.add);
      addTearDown(subscription.cancel);

      final assetA = AssetId('pkg', 'lib/a.dart');
      final assetB = AssetId('pkg', 'lib/b.dart');

      unawaited(scheduler.enqueue({assetA: ChangeType.MODIFY}));
      await startedFirstBuild.future;
      unawaited(scheduler.enqueue({assetA: ChangeType.REMOVE}));
      unawaited(scheduler.enqueue({assetB: ChangeType.ADD}));
      releaseFirstBuild.complete();

      await scheduler.waitForIdle();

      expect(capturedBatches, hasLength(2));
      expect(capturedBatches.first, {assetA: ChangeType.MODIFY});
      expect(capturedBatches.last, {
        assetA: ChangeType.REMOVE,
        assetB: ChangeType.ADD,
      });
      expect(scheduledResults, hasLength(2));
      expect(scheduledResults.first.updates, {assetA: ChangeType.MODIFY});
      expect(scheduledResults.last.updates, {
        assetA: ChangeType.REMOVE,
        assetB: ChangeType.ADD,
      });
      expect(
        scheduledResults.every((result) => result.elapsedMilliseconds >= 0),
        isTrue,
      );

      await scheduler.close();
    },
  );
}
