# Roadmap

## Program Shape

The implementation should proceed through distinct phases with measurable exit
criteria. The project is too coupled to performance claims to build blindly.

The chosen route is immediate internal integration, not wrapper-first.

## Phase Summary

### Phase 0: Planning and Constraints

Goal:

- lock architecture boundaries
- define benchmark targets
- define repository shape
- define compatibility policy

Deliverables:

- vision document
- roadmap
- implementation iterations

Status:

- in progress

### Phase 1: Repository Bootstrap

Goal:

- create repo structure
- create Dart workspace layout
- create Rust daemon crate
- create benchmark fixtures strategy
- create compatibility test harness skeleton

Deliverables:

- monorepo or multi-package workspace
- CI skeleton
- CLI shell
- daemon shell
- bootstrap strategy note and spike scaffold

### Phase 2: Dart Internal Adapter Spike

Goal:

- prove we can drive `build_runner` through internal APIs without forking
- make this the main execution path, not just an experiment
- prove we can do so from a process that has real `BuilderFactories`

Deliverables:

- minimal package importing `build_runner/src/internal.dart`
- bootstrap design around builder-factory availability
- working prototype around:
  - `BuildPlan.load(...)`
  - `BuildSeries(...)`
  - `BuildSeries.run(...)`
- alpha decision on whether to reuse:
  - `BuildSeries.filterChanges(...)`
  - `BuildSeries.checkForChanges()`
- `Bootstrapper` freshness/restart handling compatibility
- fallback to normal `build_runner`

Exit criteria:

- watch-like sequence driven by custom updates works on a small fixture
- builder-factory bootstrap path is proven feasible

### Phase 3: Rust Daemon Spike

Goal:

- prove daemon value before full integration

Deliverables:

- file watcher
- normalized event stream
- simple IPC
- project state persistence
- bootstrap-aware protocol assumptions

Exit criteria:

- daemon can emit stable update batches for fixture projects

### Phase 4: Fast Watch Alpha

Goal:

- first meaningful performance-oriented integration
- first end-to-end internal-integration product slice

Deliverables:

- `fast_build_runner watch`
- custom bootstrap entrypoint
- Rust-driven update stream
- Dart adapter invoking internal build flow directly
- alpha correctness layer around update filtering
- safe fallback behavior

Exit criteria:

- visible win on at least one medium real-world fixture
- stable repeated rebuilds

### Phase 5: Graph and Invalidation Beta

Goal:

- move from naive file changes to smarter affected-set computation
- reduce unnecessary update pressure before upstream invalidation runs

Deliverables:

- directive parser
- import graph
- affected-node propagation
- change classification

Exit criteria:

- improvement over alpha on large import-heavy fixtures

### Phase 6: Compatibility and Benchmark Beta

Goal:

- prove usefulness across the ecosystem

Deliverables:

- benchmark harness
- fixture matrix
- compatibility matrix
- regression thresholds

Exit criteria:

- at least three builder stacks work reliably:
  - `json_serializable`
  - `freezed`
  - `injectable` or `drift`
- at least one fixture covers lazy/optional or glob-driven behavior
- post-process support is either validated or explicitly deferred in docs

### Phase 7: Build Mode and AOT Expansion

Goal:

- expand from `watch` to repeated `build`
- add startup-aware optimizations

Deliverables:

- `fast_build_runner build`
- daemon reuse between invocations
- JIT/AOT policy layer

Exit criteria:

- repeated `build` is materially faster on supported fixtures

## Performance Targets

### User-Visible Targets

- no-op build: 2x-5x
- tiny incremental build: 1.5x-3x
- medium incremental build: 1.2x-2x

### Internal Targets

- daemon startup under 200ms in warm path
- normalized file event latency under 50ms for small batches
- graph update time under 100ms for small edit sets on medium projects
- Dart adapter overhead low enough to avoid eating daemon wins

## Benchmark Matrix

Benchmarks must cover:

1. Small app
   - `json_serializable`
   - tens of libraries

2. Medium app
   - `freezed + json_serializable + injectable`
   - hundreds of libraries

3. Large graph-heavy app or workspace
   - import-heavy layout
   - broad invalidation pressure

Metrics:

- initial build time
- no-op rebuild time
- one-file incremental rebuild time
- daemon warm startup time
- memory use
- failure rate

## LOC Forecast

### Watch-First Alpha

- Rust: 7k-10k
- Dart public CLI: 0.4k-0.8k
- Dart internal adapter: 1.6k-2.8k
- Total: 9.5k-13.6k

### Recommended Beta Scope

- Rust watcher and batching: 1.5k-2.5k
- Rust parser and graph: 3.0k-5.5k
- Rust persistence and IPC: 1.5k-3.0k
- Dart public CLI: 0.6k-1.0k
- Dart internal adapter: 1.8k-3.0k
- Tests and benches: 2k-4k
- Total: 14k-22k

### Broader v1 Scope

- Rust: 14k-22k
- Dart: 3k-5k
- Tests and benches: 3k-6k
- Total: 20k-33k

## Risk Register

### Risk: BuilderFactories Availability

Severity: critical

Mitigation:

- make bootstrap a first-class design topic in phase 1 and 2
- avoid assuming external process can instantiate builders directly
- keep generated-entrypoint coupling localized

### Risk: Internal API Drift

Severity: high

Mitigation:

- pin supported `build_runner` versions
- integration tests by version range
- isolate internal usage into one Dart package
- isolate bootstrap-specific coupling too

### Risk: Performance Win Too Small

Severity: high

Mitigation:

- build benchmark harness early
- do not overbuild architecture before proving gains
- kill weak ideas quickly
- specifically measure wins against the real `BuildSeries.run(...)` path, not
  synthetic daemon-only metrics

### Risk: Correctness Drift vs Standard `build_runner`

Severity: high

Mitigation:

- compare generated outputs
- fixture diff checks
- default fallback path

### Risk: Rust Daemon Complexity Grows Too Fast

Severity: medium

Mitigation:

- start with watch-first scope
- avoid speculative features
- keep protocol narrow

## Merge Strategy with Upstream

The project should assume upstream is active.

Rules:

- never duplicate large upstream subsystems unless unavoidable
- prefer adapter layers over copied code
- centralize all `build_runner` internal imports
- upstream reusable hooks only after local proof

## Definition of Alpha

Alpha means:

- one command works
- one supported version range works
- benchmarks are real
- fallback exists
- logs are good enough to debug failures
- the main path already uses internal integration
- the main path is not just upstream `Watcher` with a custom watcher factory

It does not mean:

- broad ecosystem support
- stable public API
- complete serve/workspace coverage

## Definition of Beta

Beta means:

- multiple builder stacks work
- compatibility matrix exists
- regression testing exists
- performance claims are backed by fixtures
- the project can be trialed by external users
