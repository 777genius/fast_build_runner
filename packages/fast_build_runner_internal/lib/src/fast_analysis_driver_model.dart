import 'dart:async';

import 'package:analyzer/src/clients/build_resolvers/build_resolvers.dart';
import 'package:build/build.dart';
import 'package:pool/pool.dart';

import 'package:build_runner/src/build/asset_graph/graph.dart';
import 'package:build_runner/src/build/input_tracker.dart';
import 'package:build_runner/src/build/library_cycle_graph/asset_deps_loader.dart';
import 'package:build_runner/src/build/library_cycle_graph/library_cycle_graph.dart';
import 'package:build_runner/src/build/library_cycle_graph/library_cycle_graph_loader.dart';
import 'package:build_runner/src/build/library_cycle_graph/phased_asset_deps.dart';
import 'package:build_runner/src/build/library_cycle_graph/phased_reader.dart';
import 'package:build_runner/src/logging/timed_activities.dart';

import 'fast_analysis_driver_filesystem.dart';

/// Narrow fork of upstream [AnalysisDriverModel] that swaps in
/// [FastAnalysisDriverFilesystem].
///
/// This keeps the import-graph lifecycle unchanged for safety while allowing
/// the analyzer-facing in-memory filesystem to persist unchanged files across
/// incremental builds.
class FastAnalysisDriverModel {
  final _pool = Pool(1);
  PoolResource? _lock;

  final FastAnalysisDriverFilesystem filesystem = FastAnalysisDriverFilesystem();
  final LibraryCycleGraphLoader _graphLoader = LibraryCycleGraphLoader();
  final Set<LibraryCycleGraph> _syncedLibraryCycleGraphs = Set.identity();

  Future<void> takeLockAndStartBuild(AssetGraph assetGraph) async {
    _lock = await _pool.request();
    filesystem.startBuild(assetGraph.outputs.map((id) => assetGraph.get(id)!));
  }

  void endBuildAndUnlock() {
    _graphLoader.clear();
    _syncedLibraryCycleGraphs.clear();
    _lock?.release();
    _lock = null;
  }

  PhasedAssetDeps phasedAssetDeps() => _graphLoader.phasedAssetDeps();

  AssetId? lookupCachedAsset(Uri uri) {
    final assetId = FastAnalysisDriverFilesystem.parseAsset(uri);
    if (assetId == null || !filesystem.getFile(assetId.asPath).exists) {
      return null;
    }
    return assetId;
  }

  Future<void> updateDriver({
    required Future<void> Function(
      Future<void> Function(AnalysisDriverForPackageBuild),
    )
    withDriver,
    required AssetId entrypoint,
    required PhasedReader phasedReader,
    required InputTracker inputTracker,
    required bool transitive,
  }) async {
    AssetId? idToSyncOntoFilesystem;
    LibraryCycleGraph? libraryCycleGraphToSyncOntoFilesystem;

    if (transitive) {
      libraryCycleGraphToSyncOntoFilesystem = await TimedActivity.resolve
          .runAsync(() async {
            final nodeLoader = AssetDepsLoader(phasedReader);
            inputTracker.addResolverEntrypoint(entrypoint);
            return (await _graphLoader.libraryCycleGraphOf(
              nodeLoader,
              entrypoint,
            )).valueAt(phase: phasedReader.phase);
          });
    } else {
      inputTracker.add(entrypoint);
      idToSyncOntoFilesystem = entrypoint;
      await phasedReader.readAtPhase(entrypoint);
    }

    await withDriver((driver) async {
      await TimedActivity.resolve.runAsync(() async {
        final phase = phasedReader.phase;
        filesystem.phase = phase;

        Future<void> writeToFilesystem(AssetId id) async {
          final content = await phasedReader.readAtPhase(id);
          if (content.exists) {
            filesystem.writeContent(content);
          }
        }

        if (idToSyncOntoFilesystem != null) {
          await writeToFilesystem(idToSyncOntoFilesystem);
        }

        if (libraryCycleGraphToSyncOntoFilesystem != null) {
          final nextGraphs = [libraryCycleGraphToSyncOntoFilesystem];
          while (nextGraphs.isNotEmpty) {
            final nextGraph = nextGraphs.removeLast();
            if (_syncedLibraryCycleGraphs.add(nextGraph)) {
              for (final id in nextGraph.root.ids) {
                await writeToFilesystem(id);
              }
              nextGraphs.addAll(nextGraph.children);
            }
          }
        }
      });

      if (filesystem.changedPaths.isNotEmpty) {
        for (final path in filesystem.changedPaths) {
          driver.changeFile(path);
        }
        filesystem.clearChangedPaths();
        await TimedActivity.analyze.runAsync(driver.applyPendingFileChanges);
      }
    });
  }
}
