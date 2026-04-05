# Changelog

## 0.1.6

- Added a real `example/` for the hosted CLI package so pub.dev shows a working quick-start example.
- Updated the README benchmark section to show a second anonymized real-project incremental table.

## 0.1.5

- Added a real long-lived `watch` command for the current project instead of only finite `spike-watch` proof runs.
- Made the watch command clean up temporary `pubspec_overrides.yaml` state on exit.
- Updated the README quick start to point users at `fast_build_runner watch`.

## 0.1.4

- Fixed real-project `spike-watch` runs by isolating the internal runtime from the target app dependency graph.
- Verified the watch path on a large real Flutter app fixture using the published CLI flow plus `--fixture` and `--mutation-profile`.

## 0.1.3

- Fixed global `spike-watch` activation so the installed executable resolves its real package root outside the repository checkout.

## 0.1.2

- Made `spike-watch` self-contained for installed packages so it can run after activation instead of requiring a local source checkout.
- Added a pub.dev badge and updated the README quick start to use the installed `spike-watch` command directly.

## 0.1.1

- Added `--delete-conflicting-outputs` as a compatibility flag for `spike-watch`.
- Updated README quick-start examples for the watch path.

## 0.1.0

- Initial public release of `fast_build_runner`.
- Default `build` command proxies to upstream `build_runner build`.
- Experimental fast watch / incremental runtime with Dart default and optional Rust mode.
