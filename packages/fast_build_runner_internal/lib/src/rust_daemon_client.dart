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
    int debounceMs = 350,
    int timeoutMs = 15000,
  }) {
    return _send({
      'command': 'watch_once',
      'id': id,
      'path': path,
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
    final process = await Process.start(
      'cargo',
      const ['run', '--quiet'],
      workingDirectory: daemonDirectory,
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

  Future<RustDaemonResponse> ping({String id = 'ping'}) {
    return send({'command': 'ping', 'id': id});
  }

  Future<RustDaemonResponse> watchOnce({
    required String id,
    required String path,
    int debounceMs = 350,
    int timeoutMs = 15000,
  }) {
    return send({
      'command': 'watch_once',
      'id': id,
      'path': path,
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
          status: json['status']! as String,
          root: json['root']! as String,
          warnings: List<String>.from(json['warnings']! as List),
          events: List<Map<String, Object?>>.from(
            json['events']! as List,
          ).map(RustDaemonWatchEvent.fromJson).toList(),
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
  final String status;
  final String root;
  final List<RustDaemonWatchEvent> events;
  final List<String> warnings;

  const RustDaemonWatchBatchResponse({
    required this.id,
    required this.status,
    required this.root,
    required this.events,
    required this.warnings,
  }) : super('watch_batch');
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
