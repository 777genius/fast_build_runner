import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/source/file_source.dart';
import 'package:analyzer/src/clients/build_resolvers/build_resolvers.dart';
import 'package:analyzer/src/dart/analysis/file_content_cache.dart';
import 'package:build/build.dart' hide Resource;
import 'package:path/path.dart' as p;

import 'package:build_runner/src/build/asset_graph/node.dart';
import 'package:build_runner/src/build/resolver/analysis_driver_filesystem.dart'
    show BuildRunnerFileContent;

/// Narrow fork of upstream [AnalysisDriverFilesystem].
///
/// The stock implementation clears the entire in-memory analyzer filesystem on
/// every build. For long-lived watch sessions that means source files which did
/// not change are re-added and re-marked as changed for analysis bookkeeping.
///
/// This version retains filesystem contents across builds and only:
/// - drops generated paths that disappeared from the asset graph
/// - updates generated phase visibility metadata
/// - marks paths changed when content or visibility actually changes
class FastAnalysisDriverFilesystem
    implements UriResolver, ResourceProvider, FileContentCache {
  final Map<String, FileContent> _data = {};
  final Set<String> _changedPaths = {};

  final Map<String, int> _phaseByPath = {};
  final Map<int, List<String>> _pathByPhase = {};

  int _phase = 0;

  int get phase => _phase;

  set phase(int phase) {
    if (phase == _phase) return;
    final previousPhase = _phase;
    _phase = phase;

    for (final entry in _pathByPhase.entries) {
      final previouslyWasVisible = previousPhase > entry.key;
      final isVisible = phase > entry.key;
      if (previouslyWasVisible != isVisible) {
        for (final path in entry.value) {
          if (_data.containsKey(path)) {
            _changedPaths.add(path);
          }
        }
      }
    }
  }

  void startBuild(Iterable<AssetNode> generatedNodes) {
    final previousPhaseByPath = Map<String, int>.from(_phaseByPath);
    final nextPhaseByPath = <String, int>{};
    final nextPathByPhase = <int, List<String>>{};

    for (final node in generatedNodes) {
      final phase = node.generatedNodeConfiguration!.phaseNumber;
      final idAsPath = node.id.asPath;
      nextPhaseByPath[idAsPath] = phase;
      nextPathByPhase.putIfAbsent(phase, () => []).add(idAsPath);
    }

    final removedGeneratedPaths = previousPhaseByPath.keys.toSet()
      ..removeAll(nextPhaseByPath.keys);
    for (final path in removedGeneratedPaths) {
      final previousPhase = previousPhaseByPath[path]!;
      final wasVisible = _phase > previousPhase;
      if (_data.remove(path) != null && wasVisible) {
        _changedPaths.add(path);
      }
    }

    for (final entry in previousPhaseByPath.entries) {
      final path = entry.key;
      final nextPhase = nextPhaseByPath[path];
      if (nextPhase == null || nextPhase == entry.value || !_data.containsKey(path)) {
        continue;
      }
      final previouslyWasVisible = _phase > entry.value;
      final isVisible = _phase > nextPhase;
      if (previouslyWasVisible != isVisible) {
        _changedPaths.add(path);
      }
    }

    _phaseByPath
      ..clear()
      ..addAll(nextPhaseByPath);
    _pathByPhase
      ..clear()
      ..addAll(nextPathByPhase);
  }

  int _phaseOf(String path) => _phaseByPath[path] ?? -1;

  bool exists(String path) => _data.containsKey(path) && _phase > _phaseOf(path);

  String read(String path) {
    if (!exists(path)) throw StateError('Read of non-existent file.');
    return _data[path]!.content;
  }

  void writeContent(BuildRunnerFileContent content) {
    if (!content.exists) throw ArgumentError('content must exist');
    final path = content.path;
    final previousContent = _data[path];
    final isVisible = _phase > _phaseOf(path);

    if (previousContent == null) {
      _data[path] = content;
      if (isVisible) {
        _changedPaths.add(path);
      }
      return;
    }

    if (content.contentHash == previousContent.contentHash) {
      return;
    }

    _data[path] = content;
    if (isVisible) {
      _changedPaths.add(path);
    }
  }

  Iterable<String> get changedPaths => _changedPaths;

  void clearChangedPaths() => _changedPaths.clear();

  @override
  FileContent get(String path) =>
      exists(path) ? _data[path]! : BuildRunnerFileContent.missing(path);

  @override
  void invalidate(String path) {}

  @override
  void invalidateAll() {}

  @override
  Uri pathToUri(String path) {
    if (!path.startsWith('/')) {
      throw ArgumentError.value('path', path, 'Must start with "/". ');
    }
    final pathSegments = path.split('/');
    final packageName = pathSegments[1];
    if (pathSegments[2] == 'lib') {
      return Uri(
        scheme: 'package',
        pathSegments: [packageName].followedBy(pathSegments.skip(3)),
      );
    } else {
      return Uri(
        scheme: 'asset',
        pathSegments: [packageName].followedBy(pathSegments.skip(2)),
      );
    }
  }

  @override
  Source? resolveAbsolute(Uri uri, [Uri? actualUri]) {
    final assetId = parseAsset(uri);
    if (assetId == null) return null;

    final file = getFile(assetPath(assetId));
    return FileSource(file, assetId.uri);
  }

  static String assetPath(AssetId assetId) => '/${assetId.package}/${assetId.path}';

  static String assetPathFor({required String package, required String path}) =>
      '/$package/$path';

  static AssetId? parseAsset(Uri uri) {
    if (uri.isScheme('package') || uri.isScheme('asset')) {
      return AssetId.resolve(uri);
    }
    if (uri.isScheme('file')) {
      if (!uri.path.startsWith('/')) {
        throw ArgumentError.value('uri.path', uri.path, 'Must start with "/". ');
      }
      final parts = uri.path.split('/');
      return AssetId(parts[1], parts.skip(2).join('/'));
    }
    return null;
  }

  @override
  p.Context get pathContext => p.posix;

  @override
  File getFile(String path) => _FastResource(this, path);

  @override
  Folder getFolder(String path) => _FastResource(this, path);

  @override
  Link getLink(String path) => throw UnimplementedError();

  @override
  Resource getResource(String path) => throw UnimplementedError();

  @override
  Folder? getStateLocation(String pluginId) => throw UnimplementedError();
}

class _FastResource implements File, Folder {
  final FastAnalysisDriverFilesystem _filesystem;

  @override
  final String path;

  _FastResource(this._filesystem, this.path);

  @override
  bool get exists => _filesystem.exists(path);

  @override
  int get hashCode => Object.hash(_filesystem, path);

  @override
  bool operator ==(Object other) =>
      other is _FastResource &&
      identical(other._filesystem, _filesystem) &&
      other.path == path;

  @override
  String readAsStringSync() => _filesystem.read(path);

  @override
  String get shortName => p.basename(path);

  @override
  Uri toUri() => _filesystem.pathToUri(path);

  @override
  int get modificationStamp {
    final content = _filesystem.get(path);
    return Object.hash(content.contentHash, content.exists);
  }

  @override
  bool isOrContains(String path) => p.isWithin(this.path, path) || this.path == path;

  @override
  String toString() => path;

  @override
  _FastResource copyTo(Folder _) => throw UnimplementedError();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

extension FastAssetIdFilesystemPath on AssetId {
  String get asPath => FastAnalysisDriverFilesystem.assetPath(this);
}
