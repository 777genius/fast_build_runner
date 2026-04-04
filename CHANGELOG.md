# Changelog

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
