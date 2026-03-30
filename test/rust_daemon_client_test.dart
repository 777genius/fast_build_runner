import 'dart:async';
import 'dart:io';

import 'package:fast_build_runner_internal/fast_build_runner_internal.dart';
import 'package:test/test.dart';

void main() {
  final repoRoot = Directory.current.path;
  final daemonDirectory = '$repoRoot/native/daemon';

  test(
    'rust daemon ping responds with protocol metadata',
    () async {
      final client = RustDaemonClient(daemonDirectory: daemonDirectory);
      final response = await client.ping(id: 'ping-test');

      expect(response, isA<RustDaemonPongResponse>());
      final pong = response as RustDaemonPongResponse;
      expect(pong.id, 'ping-test');
      expect(pong.protocolVersion, 3);
      expect(pong.daemon, 'fast_build_runner_daemon');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'rust daemon watchOnce reports a file modification batch',
    () async {
      final client = RustDaemonClient(daemonDirectory: daemonDirectory);
      final tempDir = await Directory.systemTemp.createTemp(
        'fbr-rust-daemon-test-',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.txt')
        ..writeAsStringSync('seed\n');
      unawaited(
        Future<void>.delayed(const Duration(seconds: 3), () async {
          file.writeAsStringSync(
            'changed\n',
            mode: FileMode.append,
            flush: true,
          );
        }),
      );

      final response = await client.watchOnce(
        id: 'watch-test',
        path: tempDir.path,
        debounceMs: 250,
        timeoutMs: 7000,
      );

      if (response case RustDaemonErrorResponse(:final message)) {
        fail(
          'Rust daemon returned an error payload instead of a watch batch: $message',
        );
      }
      expect(response, isA<RustDaemonWatchBatchResponse>());
      final batch = response as RustDaemonWatchBatchResponse;
      expect(batch.id, 'watch-test');
      expect(batch.status, 'ok');
      expect(batch.events, isNotEmpty);
      expect(
        batch.events.any((event) => event.path.endsWith('sample.txt')),
        isTrue,
      );
      expect(
        batch.events.any(
          (event) =>
              event.path.endsWith('sample.txt') && event.kind == 'modify',
        ),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'rust daemon session handles multiple requests in one process',
    () async {
      final session = await RustDaemonSession.start(
        daemonDirectory: daemonDirectory,
      );
      addTearDown(session.close);

      final ping = await session.ping(id: 'session-ping');
      expect(ping, isA<RustDaemonPongResponse>());
      final pong = ping as RustDaemonPongResponse;
      expect(pong.id, 'session-ping');
      expect(pong.protocolVersion, 3);

      final tempDir = await Directory.systemTemp.createTemp(
        'fbr-rust-daemon-session-test-',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.txt')
        ..writeAsStringSync('seed\n');
      unawaited(
        Future<void>.delayed(const Duration(seconds: 3), () async {
          file.writeAsStringSync(
            'changed\n',
            mode: FileMode.append,
            flush: true,
          );
        }),
      );

      final response = await session.watchOnce(
        id: 'session-watch',
        path: tempDir.path,
        debounceMs: 250,
        timeoutMs: 7000,
      );

      if (response case RustDaemonErrorResponse(:final message)) {
        fail('Rust daemon session returned an error payload: $message');
      }
      expect(response, isA<RustDaemonWatchBatchResponse>());
      final batch = response as RustDaemonWatchBatchResponse;
      expect(batch.id, 'session-watch');
      expect(
        batch.events.any(
          (event) =>
              event.path.endsWith('sample.txt') && event.kind == 'modify',
        ),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'rust daemon session supports explicit startWatch and finishWatch',
    () async {
      final session = await RustDaemonSession.start(
        daemonDirectory: daemonDirectory,
      );
      addTearDown(session.close);

      final tempDir = await Directory.systemTemp.createTemp(
        'fbr-rust-daemon-handshake-test-',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.txt')
        ..writeAsStringSync('seed\n');

      final startResponse = await session.startWatch(
        id: 'handshake-start',
        watchId: 'handshake-watch',
        path: tempDir.path,
        trackedPaths: [file.path],
        warmupMs: 250,
      );

      if (startResponse case RustDaemonErrorResponse(:final message)) {
        fail('Rust daemon startWatch returned an error payload: $message');
      }
      expect(startResponse, isA<RustDaemonWatchReadyResponse>());
      final ready = startResponse as RustDaemonWatchReadyResponse;
      expect(ready.id, 'handshake-start');
      expect(ready.watchId, 'handshake-watch');
      expect(ready.status, 'ready');

      file.writeAsStringSync('changed\n', mode: FileMode.append, flush: true);

      final finishResponse = await session.finishWatch(
        id: 'handshake-finish',
        watchId: 'handshake-watch',
        debounceMs: 250,
        timeoutMs: 7000,
      );

      if (finishResponse case RustDaemonErrorResponse(:final message)) {
        fail('Rust daemon finishWatch returned an error payload: $message');
      }
      expect(finishResponse, isA<RustDaemonWatchBatchResponse>());
      final batch = finishResponse as RustDaemonWatchBatchResponse;
      expect(batch.id, 'handshake-finish');
      expect(batch.watchId, 'handshake-watch');
      expect(
        batch.events.any(
          (event) =>
              event.path.endsWith('sample.txt') && event.kind == 'modify',
        ),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'rust daemon session can keep an active watch alive across multiple batches',
    () async {
      final session = await RustDaemonSession.start(
        daemonDirectory: daemonDirectory,
      );
      addTearDown(session.close);

      final tempDir = await Directory.systemTemp.createTemp(
        'fbr-rust-daemon-persistent-watch-test-',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.txt')
        ..writeAsStringSync('seed\n');

      final startResponse = await session.startWatch(
        id: 'persistent-start',
        watchId: 'persistent-watch',
        path: tempDir.path,
        trackedPaths: [file.path],
        warmupMs: 250,
      );
      if (startResponse case RustDaemonErrorResponse(:final message)) {
        fail(
          'Rust daemon persistent startWatch returned an error payload: $message',
        );
      }
      expect(startResponse, isA<RustDaemonWatchReadyResponse>());

      file.writeAsStringSync('changed-1\n', mode: FileMode.append, flush: true);
      final firstBatch = await session.finishWatch(
        id: 'persistent-batch-1',
        watchId: 'persistent-watch',
        debounceMs: 250,
        timeoutMs: 7000,
        keepAlive: true,
      );
      if (firstBatch case RustDaemonErrorResponse(:final message)) {
        fail(
          'Rust daemon persistent batch #1 returned an error payload: $message',
        );
      }
      expect(firstBatch, isA<RustDaemonWatchBatchResponse>());
      expect(
        (firstBatch as RustDaemonWatchBatchResponse).events.any(
          (event) =>
              event.path.endsWith('sample.txt') && event.kind == 'modify',
        ),
        isTrue,
      );

      file.writeAsStringSync('changed-2\n', mode: FileMode.append, flush: true);
      final secondBatch = await session.finishWatch(
        id: 'persistent-batch-2',
        watchId: 'persistent-watch',
        debounceMs: 250,
        timeoutMs: 7000,
      );
      if (secondBatch case RustDaemonErrorResponse(:final message)) {
        fail(
          'Rust daemon persistent batch #2 returned an error payload: $message',
        );
      }
      expect(secondBatch, isA<RustDaemonWatchBatchResponse>());
      expect(
        (secondBatch as RustDaemonWatchBatchResponse).events.any(
          (event) =>
              event.path.endsWith('sample.txt') && event.kind == 'modify',
        ),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
