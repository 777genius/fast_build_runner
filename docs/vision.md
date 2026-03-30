# Vision

## Project Definition

`fast_build_runner` is a companion build acceleration tool for
Flutter/Dart projects that use `build_runner`.

The project is intentionally positioned between a thin wrapper and a fork:

- it is **not** a passive shell script around `dart run build_runner`
- it is **not** a full fork of `dart-lang/build`
- it **does** use `build_runner` internal APIs where needed
- it **does** introduce a Rust daemon for performance-critical orchestration

## Product Goal

Ship a tool that Flutter/Dart developers can adopt because it makes their
daily edit-run-regenerate loop noticeably faster, especially in:

- `watch` mode
- repeated builds with small edits
- no-op or near-no-op rebuilds
- medium and large apps with broad import graphs

## Strategic Position

The project should be understandable as:

> A faster incremental execution layer for `build_runner`, not a replacement
> for Dart builders.

This framing matters because it preserves compatibility with the current
ecosystem and keeps the implementation scope survivable.

## Architectural Thesis

The biggest near-term opportunity is not rewriting all of build execution.
It is extracting and optimizing the hot incremental path:

- file watching
- change batching
- import / directive scanning
- dependency graph maintenance
- affected input computation
- persistent daemon state
- smarter update propagation into `build_runner`

The following pieces stay in Dart for now:

- `analyzer`
- builder factories
- builder execution
- actual generated output semantics
- `build_runner` build plan and execution machinery

## Why Rust

Rust is justified here because the target problems are dominated by:

- long-lived daemon state
- graph-heavy logic
- fast filesystem event processing
- efficient serialization
- deterministic low-overhead incremental infrastructure

Rust is **not** being chosen because "Rust is faster" in the abstract.
It is being chosen for the specific subsystems where the performance model
matches its strengths.

## Chosen Strategy

The project is explicitly choosing:

> Strong acceleration through internal integration from the start.

This is now a fixed decision.

The project is **not** following a wrapper-first path as the main line.

## Why Internal Integration Instead of Pure Wrapper

A pure wrapper can improve:

- startup ergonomics
- fallback selection
- caching around command execution
- no-op avoidance in limited cases

But it cannot strongly accelerate the build pipeline because it cannot inject
better update semantics deep enough into the system.

The internal integration route is therefore:

- acceptable
- realistic
- worth the complexity

provided that we keep the integration surface narrow and version-pinned.

## The Core Integration Model

The central technical idea is:

1. `fast_build_runner` owns a custom bootstrap path compatible with upstream
   build-script generation.
2. The Rust daemon owns project-level incremental state.
3. A Dart adapter running in the builder-capable process receives normalized
   updates from the daemon.
4. The Dart adapter uses `build_runner` internal APIs to create:
   - `BuildPlan`
   - `BuildSeries`
5. The Dart adapter feeds update maps into `BuildSeries.run(...)`.
6. `build_runner` still executes builders and manages the actual build graph.

The key nuances from the real upstream code are:

- runtime `BuilderFactories` are not directly exposed to an external tool
- upstream generates a build entrypoint script that constructs them
- the child process launched from that script is where build execution happens

- our updates enter at `BuildSeries.run(...)`
- `BuildSeries` then creates `Build`
- `Build` calls `_updateAssetGraph(...)`
- `_updateAssetGraph(...)` calls `AssetGraph.updateAndInvalidate(...)`

So we do **not** replace the internal invalidation model outright. We improve
the quality and timing of updates entering that model.

This means we accelerate the path *before and around* build execution, while
still leaning on the existing ecosystem for correctness.

It also means our first-class integration problem is actually:

- bootstrap + builder-factory availability

and only then:

- fast incremental update delivery into `BuildSeries`

It also means the first realistic win comes from:

- fewer noisy filesystem-driven updates
- better batching
- better path normalization
- better affected-set preclassification
- less unnecessary rebuild scheduling pressure

and not from bypassing core build graph semantics entirely.

It also means alpha should likely reuse a small amount of upstream logic on
purpose:

- `BuildSeries.filterChanges(...)` for tricky update normalization
- `BuildSeries.checkForChanges()` for recovery/resync

That still counts as owning the watch loop, because upstream `Watcher` is not
driving scheduling or file collection.

## User-Facing Modes

The project should evolve through these user-facing modes:

### Mode A: Fast Watch with Internal Integration

Primary target for early adoption.

- `fast_build_runner watch`
- long-lived daemon
- smart updates fed into `BuildSeries.run(...)`
- best chance at visible user-perceived gains

This mode should deliberately avoid using upstream `Watcher` as the main loop,
because upstream `Watcher` still performs its own:

- file watching pipeline
- change debouncing
- `BuildSeries.filterChanges(...)`
- build scheduling

which would weaken the value of our daemon.

Clarification:

- reusing `BuildSeries.filterChanges(...)` inside our own loop is acceptable
- the non-goal is upstream `Watcher` as owner of the loop

### Mode B: Fast Build

Second target.

- `fast_build_runner build`
- daemon reuse where available
- improved repeated build behavior
- safe fallback to normal `build_runner`

### Mode C: AOT-Aware Execution

Third target.

- smart decision between JIT and AOT
- preserved compatibility
- optimized repeated build startup

## Performance Hypothesis

The current realistic expectation is:

- `no-op build`: 2x-5x
- small incremental edit: 1.5x-3x
- medium incremental on large apps: 1.2x-2x
- analyzer-heavy pathological rebuilds: 1.1x-1.7x
- clean build: 1.0x-1.3x

These are not promises. They are target bands to validate with benchmarks.

## Success Criteria

The project is succeeding if users say:

- "watch is noticeably faster"
- "minor edits stop feeling expensive"
- "I can keep my current builders"
- "it fails safe and falls back cleanly"

The project is not succeeding if users say:

- "it is fast sometimes but breaks unpredictably"
- "it only works on toy examples"
- "I had to rewrite my build setup"
- "it fights upstream every release"

## Compatibility Principles

We will preserve these principles:

- same builders
- same generated outputs
- same project layout expectations
- opt-in adoption
- safe fallback path

We will accept these constraints:

- version pinning to supported `build_runner` ranges
- temporarily narrower support matrix
- internal API breakage across upstream updates

## Upstream Relationship

The project should not become a forever-divergent fork.

The intended relationship with `dart-lang/build` is:

- consume upstream releases
- pin and test compatible ranges
- contribute narrowly useful hooks upstream when appropriate
- avoid copying large chunks of upstream code into this repository

## Repository Evolution

The repository should evolve in stages:

1. planning and benchmark harness
2. Dart adapter spike
3. Rust daemon spike
4. internal-integration watch alpha
5. graph-driven beta
6. build-mode expansion
7. upstream hook proposals if needed

## Repository Structure

Target repository layout:

```text
fast_build_runner/
  README.md
  docs/
    vision.md
    roadmap.md
    iterations/
  packages/
    fast_build_runner/
    fast_build_runner_internal/
    fast_build_runner_bench/
  native/
    daemon/
  scripts/
  fixtures/
```

This is intentionally modular so that:

- the Dart CLI stays separate from lower-level Dart internals
- Rust code stays isolated
- benchmark fixtures can be versioned independently

## Decision Record

These decisions are fixed for now:

- project name: `fast_build_runner`
- avoid deep fork as default strategy
- target `watch` first
- start immediately with internal API usage
- Rust daemon is core, not optional scaffolding
- upstream `Watcher` is not the main fast path abstraction
- custom bootstrap path is mandatory

These decisions stay open:

- exact IPC protocol shape
- exact persistence format
- exact crate/package split
- whether `serve` joins the first public beta
