// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_runner/src/io/reader_writer.dart';
import 'package:crypto/crypto.dart';
import 'package:glob/glob.dart';

/// Defers asset graph persistence during a long-running watch session.
///
/// Upstream writes the serialized asset graph after every build. For a single
/// process watch session that state is only needed on restart, so buffering the
/// latest bytes and flushing them at the end reduces steady-state disk work.
class DeferredAssetGraphReaderWriter extends ReaderWriter {
  final ReaderWriter _delegate;
  final AssetId _assetGraphId;

  List<int>? _bufferedAssetGraphBytes;

  DeferredAssetGraphReaderWriter({
    required ReaderWriter delegate,
    required AssetId assetGraphId,
  }) : _delegate = delegate,
       _assetGraphId = assetGraphId,
       super.using(
         assetFinder: delegate.assetFinder,
         assetPathProvider: delegate.assetPathProvider,
         generatedAssetHider: delegate.generatedAssetHider,
         filesystem: delegate.filesystem,
         cache: delegate.cache,
         onDelete: delegate.onDelete,
       );

  bool get hasBufferedAssetGraphWrite => _bufferedAssetGraphBytes != null;

  Future<void> flushDeferredWrites() async {
    final bufferedAssetGraphBytes = _bufferedAssetGraphBytes;
    if (bufferedAssetGraphBytes == null) {
      return;
    }
    _bufferedAssetGraphBytes = null;
    await _delegate.writeAsBytes(_assetGraphId, bufferedAssetGraphBytes);
  }

  void discardDeferredWrites() {
    _bufferedAssetGraphBytes = null;
  }

  @override
  Future<bool> canRead(AssetId id) {
    if (id == _assetGraphId && _bufferedAssetGraphBytes != null) {
      return Future.value(true);
    }
    return _delegate.canRead(id);
  }

  @override
  Future<List<int>> readAsBytes(AssetId id) {
    if (id == _assetGraphId && _bufferedAssetGraphBytes != null) {
      return Future.value(List<int>.from(_bufferedAssetGraphBytes!));
    }
    return _delegate.readAsBytes(id);
  }

  @override
  Future<String> readAsString(AssetId id, {Encoding encoding = utf8}) async {
    if (id == _assetGraphId && _bufferedAssetGraphBytes != null) {
      return encoding.decode(_bufferedAssetGraphBytes!);
    }
    return _delegate.readAsString(id, encoding: encoding);
  }

  @override
  Future<void> writeAsBytes(AssetId id, List<int> bytes) {
    if (id == _assetGraphId) {
      _bufferedAssetGraphBytes = List<int>.from(bytes);
      return Future.value();
    }
    return _delegate.writeAsBytes(id, bytes);
  }

  @override
  Future<void> writeAsString(
    AssetId id,
    String contents, {
    Encoding encoding = utf8,
  }) {
    if (id == _assetGraphId) {
      _bufferedAssetGraphBytes = encoding.encode(contents);
      return Future.value();
    }
    return _delegate.writeAsString(id, contents, encoding: encoding);
  }

  @override
  Future<Digest> digest(AssetId id) => _delegate.digest(id);

  @override
  Future<void> delete(AssetId id) {
    if (id == _assetGraphId) {
      _bufferedAssetGraphBytes = null;
    }
    return _delegate.delete(id);
  }

  @override
  Future<void> deleteDirectory(AssetId id) {
    discardDeferredWrites();
    return _delegate.deleteDirectory(id);
  }

  @override
  Stream<AssetId> findAssets(Glob glob) => _delegate.findAssets(glob);
}
