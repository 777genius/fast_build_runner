import 'package:build/build.dart';
import 'package:fast_build_runner_internal/fast_build_runner_internal.dart';
import 'package:test/test.dart';
import 'package:watcher/watcher.dart';

void main() {
  test('watch batch resolver keeps a clean watcher update batch', () async {
    final expectedSource = AssetId('pkg', 'lib/person.dart');
    var resyncCalls = 0;

    final resolution = await resolveWatchBatch(
      watcherUpdates: {expectedSource: ChangeType.MODIFY},
      watcherBatchWasEmpty: false,
      expectedSourceAssetId: expectedSource,
      collectSourceUpdates: () async {
        resyncCalls++;
        return {expectedSource: ChangeType.MODIFY};
      },
    );

    expect(resyncCalls, 0);
    expect(resolution.usedResync, isFalse);
    expect(resolution.warning, isNull);
    expect(resolution.updates, {expectedSource: ChangeType.MODIFY});
  });

  test(
    'watch batch resolver replaces an empty watcher batch with resynced updates',
    () async {
      final expectedSource = AssetId('pkg', 'lib/person.dart');

      final resolution = await resolveWatchBatch(
        watcherUpdates: const {},
        watcherBatchWasEmpty: true,
        expectedSourceAssetId: expectedSource,
        collectSourceUpdates: () async => {expectedSource: ChangeType.MODIFY},
      );

      expect(resolution.usedResync, isTrue);
      expect(
        resolution.warning,
        contains('Replaced watcher updates with filesystem resync updates.'),
      );
      expect(resolution.updates, {expectedSource: ChangeType.MODIFY});
    },
  );

  test(
    'watch batch resolver replaces a batch that misses the expected source asset',
    () async {
      final expectedSource = AssetId('pkg', 'lib/person.dart');
      final otherAsset = AssetId('pkg', 'build.yaml');

      final resolution = await resolveWatchBatch(
        watcherUpdates: {otherAsset: ChangeType.MODIFY},
        watcherBatchWasEmpty: false,
        expectedSourceAssetId: expectedSource,
        collectSourceUpdates: () async => {expectedSource: ChangeType.MODIFY},
      );

      expect(resolution.usedResync, isTrue);
      expect(
        resolution.warning,
        contains('did not include the expected source asset'),
      );
      expect(resolution.updates, {expectedSource: ChangeType.MODIFY});
    },
  );
}
