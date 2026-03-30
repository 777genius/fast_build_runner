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
    final process = await Process.start(
      'cargo',
      const ['run', '--quiet'],
      workingDirectory: daemonDirectory,
    );

    final stdoutLines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final stderrBuffer = StringBuffer();
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write);

    process.stdin.writeln(jsonEncode(request));
    await process.stdin.close();

    final line = await stdoutLines.first.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException(
        'Timed out waiting for a Rust daemon response.',
      ),
    );

    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException(
        'Timed out waiting for the Rust daemon process to exit.',
      ),
    );
    await stderrSubscription.cancel();

    final decoded = jsonDecode(line) as Map<String, Object?>;
    final response = RustDaemonResponse.fromJson(decoded);
    if (exitCode != 0 && response is! RustDaemonErrorResponse) {
      throw StateError(
        'Rust daemon exited with code $exitCode without returning an error payload.\n'
        'stderr:\n$stderrBuffer',
      );
    }
    return response;
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
