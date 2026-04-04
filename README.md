# fast_build_runner

[![pub package](https://img.shields.io/pub/v/fast_build_runner.svg)](https://pub.dev/packages/fast_build_runner)

Faster incremental rebuilds for Dart/Flutter projects built on top of
[`build_runner`](https://pub.dev/packages/build_runner).

`fast_build_runner` keeps builders, analyzer, and generated code in Dart. It
currently focuses on speeding up the **watch / incremental** path while keeping
generated outputs aligned with upstream.

Current best public signal:

- up to **`6.66x` faster incremental rebuilds**
- generated Dart outputs verified to match upstream on a large real Flutter app
- one-shot `build` stays on the upstream `build_runner build` path
- the current optimization target is the watch / incremental workflow
- the main Dart runtime / hot-path code lives in
  [`packages/fast_build_runner_internal/lib/src/`](./packages/fast_build_runner_internal/lib/src/)

## Start Fast

Install the package:

```bash
dart pub global activate fast_build_runner
```

Use the fast runtime for watch / incremental rebuilds:

```bash
fast_build_runner watch
```

For one-shot builds, keep using the upstream build path:

```bash
fast_build_runner build --delete-conflicting-outputs
```

## Table Of Contents

- [Start Fast](#start-fast)
- [Current Headline](#current-headline)
- [What This Project Is](#what-this-project-is)
- [What This Project Is Not](#what-this-project-is-not)
- [Why It Exists](#why-it-exists)
- [Current Default](#current-default)
- [Real-World Results: Large Flutter App](#real-world-results-large-flutter-app)
- [Correctness Status](#correctness-status)
- [Quick Start](#quick-start)
- [CLI Commands](#cli-commands)
- [Architecture](#architecture)
- [Main Technical Direction](#main-technical-direction)
- [Main Constraints](#main-constraints)
- [Honest Public Positioning](#honest-public-positioning)
- [Repository Health Commands](#repository-health-commands)
- [Project Documents](#project-documents)

## Current Headline

- ✅ Up to **`6.66x` faster incremental rebuilds** on a large real Flutter app
- ✅ Up to **`1.44x` faster total watch time** on the same app
- ✅ Custom bootstrap path with real upstream `BuilderFactories`
- ✅ Custom child runtime around upstream `BuildPlan` / `BuildSeries`
- ✅ Generated Dart outputs match upstream byte-for-byte on a large real Flutter app
- ⚠️ Rust mode is still experimental

## What This Project Is

`fast_build_runner` currently experiments with three layers:

1. **Custom bootstrap**
   - Generates a custom entrypoint instead of handing everything to the stock
     `ChildProcess.run(...)`.
2. **Custom watch runtime**
   - Reuses upstream planning/build internals while controlling the watch loop,
     batching, and incremental scheduling.
3. **Alternative source engines**
   - `dart` source engine: current safe default
   - `rust` source engine: optional experimental accelerator
   - `upstream`: baseline for comparison

## What This Project Is Not

- not a full rewrite of `build_runner`
- not a full invalidation-engine replacement
- not yet a production-ready replacement for every builder topology
- not yet a solved story for workspaces / post-process / lazy phases

## Why It Exists

The practical bottleneck for many teams is not code generation itself, but:

- slow startup for repeated watch sessions
- broad invalidation after a small edit
- repeated rebuild scheduling on tiny changes
- too much work happening outside the actual tracked builder actions

The current strategy is deliberately narrow:

- keep the ecosystem-compatible parts in Dart
- fork only the hottest internal paths when needed
- measure everything on a real Flutter app instead of synthetic claims only

## Current Default

The current recommended default is:

- **`build` proxies to upstream `build_runner build`**
- **Dart source engine by default**
- **Rust source engine only as an opt-in experimental mode**
- **fast runtime is currently focused on watch / incremental workflows**

If you do not pass `--source-engine`, `fast_build_runner` already uses
`dart`.

Why this is the default:

- it already shows strong incremental wins
- it matches upstream generated Dart outputs
- it avoids the current Rust startup penalty on short sessions

## Real-World Results: Large Flutter App

Benchmarks below were run on a large private Flutter app with three mutation
profiles.

### Total Wall-Clock vs Upstream `build_runner`

| Scenario | Upstream | fast_build_runner (dart) | fast_build_runner (rust) |
| --- | ---: | ---: | ---: |
| DTO mutation | 49.74s | 43.52s (`1.14x`) | 63.45s (`0.78x`) |
| Freezed mutation | 50.39s | 43.33s (`1.16x`) | 42.84s (`1.18x`) |
| Injection mutation | 66.72s | 49.38s (`1.35x`) | 46.24s (`1.44x`) |

### Incremental Rebuild vs Upstream `build_runner`

| Scenario | Upstream | fast_build_runner (dart) | fast_build_runner (rust) |
| --- | ---: | ---: | ---: |
| DTO mutation | 4.41s | 0.97s (`4.54x`) | 0.93s (`4.76x`) |
| Freezed mutation | 8.75s | 5.02s (`1.74x`) | 4.99s (`1.75x`) |
| Injection mutation | 25.10s | 4.37s (`5.75x`) | 3.77s (`6.66x`) |

### Current Interpretation

- The **main value today is incremental rebuild speed**.
- The **Dart** mode is the current safe public story.
- The **Rust** mode already wins on some heavy cases, but still has bad total
  behavior on short DTO-style sessions because its startup cost does not always
  amortize.
- The strongest result so far is the **DI / injection-heavy** case.

## Correctness Status

The most important current correctness claim is:

- upstream `build_runner`
- `fast_build_runner --source-engine=dart`

produce the **same generated Dart outputs** on the large private Flutter app
for the current
regression scenario.

There is now a regression test for that in:

- [test/real_app_output_compatibility_test.dart](./test/real_app_output_compatibility_test.dart)

### What is expected to match

Generated code outputs such as:

- `*.g.dart`
- `*.freezed.dart`
- `*.config.dart`
- `*.gr.dart`
- `*.mocks.dart`

### What may differ without being a correctness bug

Build metadata and cache/tooling artifacts, for example:

- `.flutter-plugins-dependencies`
- `build/**/outputs.json`
- `build/**/.filecache`
- `build/**/gen_localizations.*`

Those files are not the generated API/code outputs that users review and commit.

## Quick Start

Run commands from this repository root.

### Bootstrap seam proof

```bash
/Users/belief/dev/flutter/bin/dart run bin/fast_build_runner.dart spike-bootstrap
```

### Long-lived watch loop on the default Dart engine

```bash
/Users/belief/dev/flutter/bin/dart run bin/fast_build_runner.dart watch
```

### Finite watch-alpha proof on the Rust engine

```bash
/Users/belief/dev/flutter/bin/dart run bin/fast_build_runner.dart spike-watch \
  --source-engine=rust
```

### One-shot build through the upstream path

```bash
/Users/belief/dev/flutter/bin/dart run bin/fast_build_runner.dart build \
  --delete-conflicting-outputs
```

This intentionally proxies to upstream `build_runner build`, so single builds
keep upstream cold-start behavior while `fast_build_runner` stays focused on the
watch / incremental path.

### Compare engines

```bash
/Users/belief/dev/flutter/bin/dart run bin/fast_build_runner.dart benchmark-watch \
  --include-upstream \
  --output=summary
```

### Real project benchmark on a local real app

```bash
/Users/belief/dev/flutter/bin/dart run bin/fast_build_runner.dart benchmark-watch \
  --fixture="$FAST_BUILD_RUNNER_REAL_APP_PATH" \
  --mutation-profile=profiles/real_app/analytics_service_injection.json \
  --include-upstream \
  --output=summary
```

Set `FAST_BUILD_RUNNER_REAL_APP_PATH` to your local Flutter app path first.

Example:

```bash
export FAST_BUILD_RUNNER_REAL_APP_PATH=/absolute/path/to/your/flutter_app
/Users/belief/dev/flutter/bin/dart run bin/fast_build_runner.dart benchmark-watch \
  --fixture="$FAST_BUILD_RUNNER_REAL_APP_PATH" \
  --mutation-profile=profiles/real_app/analytics_service_injection.json \
  --include-upstream \
  --output=summary
```

## CLI Commands

- `build`
  - proxies to upstream `build_runner build` for one-shot builds
- `watch`
  - runs a long-lived fast watch loop for the current project
- `spike-bootstrap`
  - proves the bootstrap seam with a generated custom entrypoint
- `spike-watch`
  - runs one finite watch/incremental proof scenario with a chosen source engine
- `benchmark-watch`
  - compares engines, optionally against upstream baseline

## Architecture

```text
target project
    |
    v
fast_build_runner CLI
    |
    v
custom generated entrypoint
    |
    v
child-side runtime
  - BuildPlan
  - BuildSeries
  - watch scheduler
  - custom perf probes
    |
    +--> Dart source engine
    |
    +--> Rust source engine
```

### Upstream dependency pin

The current research pin is:

- `2b1450e313a188a1027f04940e0e4e82372d6530`

The local upstream source-of-truth clone lives in:

- `research/dart-build/`

## Main Technical Direction

The current most promising direction is **not** "rewrite everything in Rust".

The strongest signal so far is:

- keep builders and analyzer in Dart
- use a narrow Dart-side fork for hot internal paths
- use Rust only where it genuinely helps as an optional source/watch engine

In practice that means the next strong wins are expected from:

- analysis/resolver state retention between incremental builds
- less repeated sync into the analyzer-facing filesystem
- tighter watch/update ingestion

## Main Constraints

- analyzer-heavy builders are still bounded by upstream Dart-side costs
- full build-script freshness parity is still narrower than stock upstream
- Rust is currently a source-engine experiment, not a full graph daemon
- some project profiles still show weak or negative Rust total wall-clock gain
- workspace / post-process / lazy-phase coverage is not complete yet

## Honest Public Positioning

Good:

- "experimental companion for `build_runner`"
- "real wins on a large private Flutter app"
- "generated Dart outputs match upstream in the Dart mode"
- "Rust mode is optional and still experimental"

Bad:

- "universal `build_runner` replacement"
- "Rust makes everything faster"
- "all builder topologies are solved"

## Repository Health Commands

Analyze:

```bash
/Users/belief/dev/flutter/bin/dart analyze
```

Targeted tests:

```bash
/Users/belief/dev/flutter/bin/dart test \
  test/bootstrap_spike_test.dart \
  test/real_app_output_compatibility_test.dart \
  test/watch_alpha_test.dart \
  test/watch_benchmark_test.dart \
```

Rust daemon tests:

```bash
cd native/daemon && cargo test
```

## Project Documents

- [Public Demo](./docs/public-demo.md)
- [Vision](./docs/vision.md)
- [Roadmap](./docs/roadmap.md)
- [Bootstrap Strategy](./docs/bootstrap-strategy.md)
- [Upstream Code Map](./docs/upstream-code-map.md)
- [Feasibility Assessment](./docs/feasibility-assessment.md)
- [Performance Ceiling](./docs/performance-ceiling.md)
- [Edge Cases](./docs/edge-cases.md)
- [Iteration 00: Principles](./docs/iterations/00-principles.md)
- [Iteration 01: Repository Bootstrap](./docs/iterations/01-repo-bootstrap.md)
- [Iteration 02: Dart Internal Adapter](./docs/iterations/02-dart-internal-adapter.md)
- [Iteration 03: Rust Daemon and Protocol](./docs/iterations/03-rust-daemon-and-protocol.md)
- [Iteration 04: Fast Watch Pipeline](./docs/iterations/04-fast-watch-pipeline.md)
- [Iteration 05: Graph and Invalidation Engine](./docs/iterations/05-graph-and-invalidation.md)
- [Iteration 06: Benchmarks and Compatibility](./docs/iterations/06-benchmarks-and-compatibility.md)
- [Iteration 07: Build Mode and AOT Expansion](./docs/iterations/07-build-mode-and-aot.md)
