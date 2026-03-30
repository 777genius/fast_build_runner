# fast_build_runner

`fast_build_runner` is an experimental companion for `build_runner`.

It keeps builders, analyzer, and code generation in Dart, but moves the hot
incremental orchestration path toward a Rust-backed watch/update pipeline. The
goal is not a deep fork of `dart-lang/build`, but a faster path for `watch`,
`no-op`, and small incremental rebuilds.

## Current State

What is already working in this repository:

- custom bootstrap path with real upstream `BuilderFactories`
- child-side execution path around `BuildPlan` and `BuildSeries`
- watch-alpha flow on top of that runtime
- Rust daemon with a JSON protocol and filesystem `watch_once`
- Rust-backed watch source engine wired into the custom runtime
- multi-cycle incremental watch runs
- benchmark command that compares `dart` and `rust` source engines on the same fixture

What this is **not** yet:

- a drop-in replacement for `dart run build_runner watch`
- a production-ready compatibility layer for every builder topology
- a full invalidation engine replacement
- a full workspace / post-process / lazy-phase solution

## Why This Exists

`build_runner` can be slow for several different reasons, but the most
practical place to attack first is the incremental path:

- startup and bootstrap overhead
- watcher batching and change ingestion
- broad change invalidation
- repeated rebuild scheduling on small edits

The current project direction is:

- keep `analyzer`, builders, and actual codegen in Dart
- keep upstream `build_runner` semantics as close as possible
- replace only the hot watch/update path where that gives leverage

## What To Run

All commands below run from this repository root.

Bootstrap seam proof:

```bash
/Users/belief/dev/flutter/bin/dart run bin/fast_build_runner.dart spike-bootstrap
```

Single watch-alpha run on the Dart source engine:

```bash
/Users/belief/dev/flutter/bin/dart run bin/fast_build_runner.dart spike-watch \
  --source-engine=dart
```

Single watch-alpha run on the Rust source engine:

```bash
/Users/belief/dev/flutter/bin/dart run bin/fast_build_runner.dart spike-watch \
  --source-engine=rust
```

Multi-cycle watch-alpha run:

```bash
/Users/belief/dev/flutter/bin/dart run bin/fast_build_runner.dart spike-watch \
  --source-engine=rust \
  --incremental-cycles=2
```

Benchmark summary comparing the two source engines:

```bash
/Users/belief/dev/flutter/bin/dart run bin/fast_build_runner.dart benchmark-watch \
  --incremental-cycles=1
```

The benchmark command prints machine-readable JSON with:

- elapsed milliseconds for `dart`
- elapsed milliseconds for `rust`
- nested watch-alpha results for both runs
- computed `rustSpeedupVsDart`

## Current Architecture

High-level shape:

```text
fixture / target project
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
        |
        +--> Dart watcher source engine
        |
        +--> Rust daemon source engine
```

The currently pinned upstream research commit is:

- `2b1450e313a188a1027f04940e0e4e82372d6530`

Upstream research source of truth lives in:

- `research/dart-build/`

## Useful Commands

Analyze:

```bash
/Users/belief/dev/flutter/bin/dart analyze
```

Core regression tests:

```bash
/Users/belief/dev/flutter/bin/dart test \
  test/bootstrap_spike_test.dart \
  test/watch_alpha_test.dart \
  test/rust_daemon_client_test.dart \
  test/watch_benchmark_test.dart
```

Rust daemon tests:

```bash
cd native/daemon && cargo test
```

## Main Constraints

The project still has important limits:

- analyzer-heavy builders are still bounded by upstream Dart-side costs
- full build-script freshness parity is still narrower than upstream
- the Rust daemon is currently a source-engine component, not a full graph daemon
- benchmark numbers are still dominated by upstream initial build cost on the tiny fixture

That means the current benchmark is a **correctness and integration benchmark**,
not yet a strong public performance claim.

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
