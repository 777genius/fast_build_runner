# Changelog

## 0.1.4

- Added the Dart-side live watch session used by the public `fast_build_runner watch` command.
- Added generated-asset filtering and graceful build-script restart signaling for long-running watch sessions.

## 0.1.3

- Stopped patching `fast_build_runner_internal` into target app dependencies during spike/watch runs.
- Switched the child runtime import to a file-based internal package path so real Flutter apps can run without `meta`/`flutter_test` solver conflicts.

## 0.1.2

- Made the bootstrap and watch runners work without a local `research/dart-build` checkout by falling back to hosted package constraints.
- Resolved the package root more robustly for activated executables so bundled fixtures and runtime assets are found correctly.

## 0.1.1

- Added support for passing the `delete-conflicting-outputs` compatibility flag through the watch runtime.

## 0.1.0

- Initial public release used by `fast_build_runner`.
