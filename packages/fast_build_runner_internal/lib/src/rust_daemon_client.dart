import 'dart:async';
import 'dart:convert';
import 'dart:io';

class RustDaemonClient {
  final String daemonDirectory;

  const RustDaemonClient({required this.daemonDirectory});

  Future<RustDaemonResponse> ping({String id = 'ping'}) {
    return _send({'command': 'ping', 'id': id});
  }

  Future<RustDaemonResponse> watchOnce({
    required String id,
    required String path,
    List<String>? trackedPaths,
    int debounceMs = 350,
    int timeoutMs = 15000,
  }) {
    return _send({
      'command': 'watch_once',
      'id': id,
      'path': path,
      'tracked_paths': trackedPaths,
      'debounce_ms': debounceMs,
      'timeout_ms': timeoutMs,
    });
  }

  Future<RustDaemonResponse> startWatch({
    required String id,
    required String watchId,
    required String path,
    List<String>? trackedPaths,
    int warmupMs = 250,
  }) {
    return _send({
      'command': 'start_watch',
      'id': id,
      'watch_id': watchId,
      'path': path,
      'tracked_paths': trackedPaths,
      'warmup_ms': warmupMs,
    });
  }

  Future<RustDaemonResponse> finishWatch({
    required String id,
    required String watchId,
    int debounceMs = 350,
    int timeoutMs = 15000,
  }) {
    return _send({
      'command': 'finish_watch',
      'id': id,
      'watch_id': watchId,
      'debounce_ms': debounceMs,
      'timeout_ms': timeoutMs,
    });
  }

  Future<RustDaemonResponse> _send(Map<String, Object?> request) async {
    final session = await RustDaemonSession.start(
      daemonDirectory: daemonDirectory,
    );
    try {
      return await session.send(request);
    } finally {
      await session.close();
    }
  }
}

class RustDaemonSession {
  static const _daemonExecutableBaseName = 'fast_build_runner_daemon';

  final String daemonDirectory;
  final Process _process;
  final StreamIterator<String> _stdoutIterator;
  final StringBuffer _stderrBuffer;
  final StreamSubscription<String> _stderrSubscription;

  bool _closed = false;
  Future<void> _requestQueue = Future.value();

  RustDaemonSession._({
    required this.daemonDirectory,
    required Process process,
    required StreamIterator<String> stdoutIterator,
    required StringBuffer stderrBuffer,
    required StreamSubscription<String> stderrSubscription,
  }) : _process = process,
       _stdoutIterator = stdoutIterator,
       _stderrBuffer = stderrBuffer,
       _stderrSubscription = stderrSubscription;

  static Future<RustDaemonSession> start({
    required String daemonDirectory,
  }) async {
    final executablePath = await _resolveExecutablePath(daemonDirectory);
    final process = await Process.start(
      executablePath,
      const [],
    );
    final stdoutIterator = StreamIterator<String>(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final stderrBuffer = StringBuffer();
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write);

    return RustDaemonSession._(
      daemonDirectory: daemonDirectory,
      process: process,
      stdoutIterator: stdoutIterator,
      stderrBuffer: stderrBuffer,
      stderrSubscription: stderrSubscription,
    );
  }

  static Future<String> _resolveExecutablePath(String daemonDirectory) async {
    final executableName =
        Platform.isWindows
            ? '$_daemonExecutableBaseName.exe'
            : _daemonExecutableBaseName;
    final executablePath =
        '$daemonDirectory${Platform.pathSeparator}target'
        '${Platform.pathSeparator}debug'
        '${Platform.pathSeparator}$executableName';
    final executable = File(executablePath);
    if (executable.existsSync() && !_requiresRebuild(daemonDirectory, executable)) {
      return executable.path;
    }

    final buildResult = await Process.run(
      'cargo',
      const ['build', '--quiet'],
      workingDirectory: daemonDirectory,
    );
    if (buildResult.exitCode != 0) {
      throw StateError(
        'Failed to build Rust daemon binary in $daemonDirectory\n'
        'stdout:\n${buildResult.stdout}\n'
        'stderr:\n${buildResult.stderr}',
      );
    }
    if (!executable.existsSync()) {
      throw StateError(
        'Rust daemon build completed but executable was not found at ${executable.path}.',
      );
    }
    return executable.path;
  }

  static bool _requiresRebuild(String daemonDirectory, File executable) {
    if (!executable.existsSync()) {
      return true;
    }
    final executableModified = executable.statSync().modified;
    final srcDirectory = Directory('$daemonDirectory${Platform.pathSeparator}src');
    if (srcDirectory.existsSync()) {
      for (final entity in srcDirectory.listSync(recursive: true)) {
        if (entity is File &&
            entity.statSync().modified.isAfter(executableModified)) {
          return true;
        }
      }
    }
    final manifestFiles = [
      File('$daemonDirectory${Platform.pathSeparator}Cargo.toml'),
      File('$daemonDirectory${Platform.pathSeparator}Cargo.lock'),
    ];
    for (final file in manifestFiles) {
      if (file.existsSync() && file.statSync().modified.isAfter(executableModified)) {
        return true;
      }
    }
    return false;
  }

  Future<RustDaemonResponse> ping({String id = 'ping'}) {
    return send({'command': 'ping', 'id': id});
  }

  Future<RustDaemonResponse> watchOnce({
    required String id,
    required String path,
    List<String>? trackedPaths,
    int debounceMs = 350,
    int timeoutMs = 15000,
  }) {
    return send({
      'command': 'watch_once',
      'id': id,
      'path': path,
      'tracked_paths': trackedPaths,
      'debounce_ms': debounceMs,
      'timeout_ms': timeoutMs,
    });
  }

  Future<RustDaemonResponse> startWatch({
    required String id,
    required String watchId,
    required String path,
    List<String>? trackedPaths,
    int warmupMs = 250,
  }) {
    return send({
      'command': 'start_watch',
      'id': id,
      'watch_id': watchId,
      'path': path,
      'tracked_paths': trackedPaths,
      'warmup_ms': warmupMs,
    });
  }

  Future<RustDaemonResponse> finishWatch({
    required String id,
    required String watchId,
    int debounceMs = 350,
    int timeoutMs = 15000,
  }) {
    return send({
      'command': 'finish_watch',
      'id': id,
      'watch_id': watchId,
      'debounce_ms': debounceMs,
      'timeout_ms': timeoutMs,
    });
  }

  Future<RustDaemonResponse> send(Map<String, Object?> request) async {
    if (_closed) {
      throw StateError('RustDaemonSession is already closed.');
    }

    final responseFuture = _requestQueue.then((_) => _sendInternal(request));
    _requestQueue = responseFuture.then<void>((_) {}, onError: (_, _) {});
    return responseFuture;
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _requestQueue.catchError((_) {});
    await _process.stdin.close();
    await _stdoutIterator.cancel();
    final exitCode = await _process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException(
        'Timed out waiting for the Rust daemon session to exit.',
      ),
    );
    await _stderrSubscription.cancel();
    if (exitCode != 0) {
      throw StateError(
        'Rust daemon session exited with code $exitCode.\n'
        'stderr:\n$_stderrBuffer',
      );
    }
  }

  Future<RustDaemonResponse> _sendInternal(Map<String, Object?> request) async {
    _process.stdin.writeln(jsonEncode(request));
    await _process.stdin.flush();

    final hasLine = await _stdoutIterator.moveNext().timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException(
        'Timed out waiting for a Rust daemon session response.',
      ),
    );
    if (!hasLine) {
      final exitCode = await _process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -999,
      );
      throw StateError(
        'Rust daemon session closed before returning a response.\n'
        'exitCode: $exitCode\n'
        'stderr:\n$_stderrBuffer',
      );
    }

    final decoded = jsonDecode(_stdoutIterator.current) as Map<String, Object?>;
    return RustDaemonResponse.fromJson(decoded);
  }
}

sealed class RustDaemonResponse {
  final String kind;

  const RustDaemonResponse(this.kind);

  static RustDaemonResponse fromJson(Map<String, Object?> json) {
    final kind = json['kind'];
    if (kind is! String) {
      throw StateError('Rust daemon response is missing a string kind.');
    }
    switch (kind) {
      case 'pong':
        return RustDaemonPongResponse(
          id: json['id']! as String,
          protocolVersion: json['protocol_version']! as int,
          daemon: json['daemon']! as String,
        );
      case 'watch_batch':
        return RustDaemonWatchBatchResponse(
          id: json['id']! as String,
          watchId: json['watch_id'] as String?,
          status: json['status']! as String,
          root: json['root']! as String,
          warnings: List<String>.from(json['warnings']! as List),
          events: List<Map<String, Object?>>.from(
            json['events']! as List,
          ).map(RustDaemonWatchEvent.fromJson).toList(),
        );
      case 'watch_ready':
        return RustDaemonWatchReadyResponse(
          id: json['id']! as String,
          watchId: json['watch_id']! as String,
          status: json['status']! as String,
          root: json['root']! as String,
        );
      case 'error':
        return RustDaemonErrorResponse(
          id: json['id'] as String?,
          message: json['message']! as String,
        );
      default:
        throw StateError('Unsupported Rust daemon response kind: $kind');
    }
  }
}

class RustDaemonPongResponse extends RustDaemonResponse {
  final String id;
  final int protocolVersion;
  final String daemon;

  const RustDaemonPongResponse({
    required this.id,
    required this.protocolVersion,
    required this.daemon,
  }) : super('pong');
}

class RustDaemonWatchBatchResponse extends RustDaemonResponse {
  final String id;
  final String? watchId;
  final String status;
  final String root;
  final List<RustDaemonWatchEvent> events;
  final List<String> warnings;

  const RustDaemonWatchBatchResponse({
    required this.id,
    required this.watchId,
    required this.status,
    required this.root,
    required this.events,
    required this.warnings,
  }) : super('watch_batch');
}

class RustDaemonWatchReadyResponse extends RustDaemonResponse {
  final String id;
  final String watchId;
  final String status;
  final String root;

  const RustDaemonWatchReadyResponse({
    required this.id,
    required this.watchId,
    required this.status,
    required this.root,
  }) : super('watch_ready');
}

class RustDaemonErrorResponse extends RustDaemonResponse {
  final String? id;
  final String message;

  const RustDaemonErrorResponse({
    required this.id,
    required this.message,
  }) : super('error');
}

class RustDaemonWatchEvent {
  final String path;
  final String kind;

  const RustDaemonWatchEvent({required this.path, required this.kind});

  static RustDaemonWatchEvent fromJson(Map<String, Object?> json) =>
      RustDaemonWatchEvent(
        path: json['path']! as String,
        kind: json['kind']! as String,
      );
}
