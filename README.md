# fast_build_runner

`fast_build_runner` is a companion tool for `build_runner` focused on making
incremental Flutter/Dart code generation faster without forking the whole
`dart-lang/build` stack.

The project direction is:

- keep `analyzer`, builders, and code generation in Dart
- move hot-path incremental orchestration into a Rust daemon
- integrate with `build_runner` through internal APIs instead of a deep fork
- optimize `watch`, `no-op`, and small incremental builds first

## Core Idea

`fast_build_runner` does not try to replace the whole build ecosystem.
Instead, it aims to:

- watch files faster
- maintain a persistent import/dependency graph
- compute affected inputs quickly
- batch and classify file changes
- feed smarter updates into `build_runner`

## Why This Exists

`build_runner` performance problems are real, but they are not all caused by
one thing. The current evidence points to a mix of:

- startup overhead
- import graph invalidation
- repeated parsing / dependency analysis
- analyzer-heavy builders
- unnecessary or overly broad rebuild scheduling

The highest-leverage place for a new implementation is the incremental path,
not a full rewrite of analyzer or builder execution.

## Project Documents

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

## Current Scope

The chosen implementation path is immediate **internal integration**.

That means the first serious implementation is not a weak wrapper-only MVP.
It is:

- Rust daemon manages file watching and project graph state
- Dart internal adapter drives `BuildPlan` and `BuildSeries`
- updates are supplied by our own integration layer
- alpha may still reuse `BuildSeries.filterChanges(...)` and
  `checkForChanges()` for correctness
- standard `build_runner` remains the fallback path

The project is therefore explicitly targeting strong acceleration from the
start, while still avoiding a deep upstream fork.

The currently pinned upstream `build_runner` research commit is:

- `2b1450e313a188a1027f04940e0e4e82372d6530`

One major constraint from the real upstream code is now fixed in the plan:

- external code does not directly get runtime `BuilderFactories`
- upstream materializes them inside the generated build script entrypoint

So `fast_build_runner` must include a custom bootstrap path, not only a custom
watch loop.

## Upstream Study Basis

The planning in this repository is based on a local clone of `dart-lang/build`
kept under:

- `research/dart-build/`

That clone is used as the source of truth for:

- internal entry points
- restart/freshness flow
- build graph update semantics
- watcher integration limits
- resolver concurrency limits
- secondary-input invalidation behavior
- optional/lazy and post-process semantics

## High-Level Non-Goals

- replacing `analyzer`
- rewriting builders
- forking `dart-lang/build` long-term
- immediately supporting every `serve` and workspace edge case

## Status

Planning and implementation scaffolding.
