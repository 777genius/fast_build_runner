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
        onBuild: (updates, {required skipBuildScriptFreshnessCheck}) async {
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

      unawaited(
        scheduler.enqueue({
          assetA: ChangeType.MODIFY,
        }, skipBuildScriptFreshnessCheck: true),
      );
      await startedFirstBuild.future;
      unawaited(
        scheduler.enqueue({
          assetA: ChangeType.REMOVE,
        }, skipBuildScriptFreshnessCheck: true),
      );
      unawaited(
        scheduler.enqueue({
          assetB: ChangeType.ADD,
        }, skipBuildScriptFreshnessCheck: true),
      );
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

  test(
    'watch scheduler waits briefly after a build to coalesce late-arriving batches',
    () async {
      final startedFirstBuild = Completer<void>();
      final releaseFirstBuild = Completer<void>();
      final capturedBatches = <Map<AssetId, ChangeType>>[];
      final assetA = AssetId('pkg', 'lib/a.dart');
      final assetB = AssetId('pkg', 'lib/b.dart');
      final assetC = AssetId('pkg', 'lib/c.dart');

      final scheduler = FastWatchScheduler<Map<AssetId, ChangeType>>(
        onBuild: (updates, {required skipBuildScriptFreshnessCheck}) async {
          capturedBatches.add(Map<AssetId, ChangeType>.from(updates));
          if (capturedBatches.length == 1) {
            startedFirstBuild.complete();
            await releaseFirstBuild.future;
          }
          return updates;
        },
        postBuildSettleDelay: const Duration(milliseconds: 80),
      );

      unawaited(
        scheduler.enqueue({
          assetA: ChangeType.MODIFY,
        }, skipBuildScriptFreshnessCheck: true),
      );
      await startedFirstBuild.future;
      unawaited(
        scheduler.enqueue({
          assetB: ChangeType.ADD,
        }, skipBuildScriptFreshnessCheck: true),
      );
      releaseFirstBuild.complete();
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 20), () {
          return scheduler.enqueue({
            assetC: ChangeType.MODIFY,
          }, skipBuildScriptFreshnessCheck: true);
        }),
      );

      await scheduler.waitForIdle();

      expect(capturedBatches, hasLength(2));
      expect(capturedBatches.first, {assetA: ChangeType.MODIFY});
      expect(capturedBatches.last, {
        assetB: ChangeType.ADD,
        assetC: ChangeType.MODIFY,
      });

      await scheduler.close();
    },
  );

  test(
    'watch scheduler can force a build even when updates are empty',
    () async {
      final buildInvocations = <bool>[];
      final scheduler = FastWatchScheduler<void>(
        onBuild: (updates, {required skipBuildScriptFreshnessCheck}) async {
          buildInvocations.add(skipBuildScriptFreshnessCheck);
        },
      );

      await scheduler.enqueue(
        const <AssetId, ChangeType>{},
        skipBuildScriptFreshnessCheck: false,
      );
      await scheduler.waitForIdle();

      expect(buildInvocations, [false]);
      await scheduler.close();
    },
  );
}
