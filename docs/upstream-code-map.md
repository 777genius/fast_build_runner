# Upstream Code Map

## Purpose

This document anchors `fast_build_runner` planning to the real upstream code in
the local clone:

- `research/dart-build/`

It exists to stop the project from drifting into architecture based on guesses.

## Local Upstream Clone

Repository:

- `research/dart-build/`

Main package of interest:

- `research/dart-build/build_runner/`

## Core Files and Their Roles

### `build_runner/lib/src/internal.dart`

Role:

- exports a subset of internal classes we can consume from a separate package

Important:

- it exports `BuildPlan`, `BuildSeries`, `BuildOptions`, `BuilderFactories`,
  `ReaderWriter`, and related types
- it does **not** export everything
- notably, `commands/watch/watcher.dart` is not re-exported here

Implication:

- our integration should prefer `BuildPlan` and `BuildSeries`
- any direct dependency on non-exported internals increases fragility

### `build_runner/lib/src/build_runner.dart`

Role:

- top-level tool orchestration
- command parsing
- builder bootstrapping

Important:

- the standard path either bootstraps builders or constructs commands like
  `BuildCommand` and `WatchCommand`
- `BuildCommand` and `WatchCommand` both require a real `BuilderFactories`
  instance

Implication:

- we should not try to wrap the entire upstream CLI internally
- we should build our own CLI and call lower layers directly

Constraint:

- lower layers are only usable after solving builder-factory bootstrap

### `build_runner/lib/src/build_plan/build_plan.dart`

Role:

- loads package/build configuration
- checks compiled build script freshness through `Bootstrapper`
- loads or creates asset graph
- computes initial `updates`
- computes restart requirements

Important:

- `BuildPlan.load(...)` is a major seam
- `BuildPlan.reload()` is the correct path for config-change handling

Implication:

- our adapter must preserve this lifecycle
- we should not duplicate config/build-plan loading logic in Rust

But:

- `BuildPlan.load(...)` is only useful after we have entered a process with
  real `BuilderFactories`

### `build_runner/lib/src/build/build_series.dart`

Role:

- owns a sequence of builds with shared state
- receives explicit `updates`
- creates `Build`
- handles config-change reload behavior
- checks build-script freshness for subsequent builds

Important:

- `BuildSeries.run(updates, ...)` is the best integration seam
- `BuildSeries.filterChanges(...)` and `checkForChanges()` are upstream helper
  paths, but not mandatory if we run our own loop

Implication:

- our fast path should drive `BuildSeries.run(...)` directly
- we should not base the architecture on upstream `Watcher`
- but `BuildSeries.filterChanges(...)` is still valuable as an early
  correctness layer
- `BuildSeries.checkForChanges()` is a useful recovery/resync helper

Prerequisite:

- we must already be in the builder-capable execution process

### `build_runner/lib/src/bootstrap/build_script_generate.dart`

Role:

- generates the build entrypoint script
- discovers builder definitions
- emits code that constructs real `BuilderFactories`

Important:

- helper code here returns code expressions, not runtime factory instances
- runtime factories are created inside the generated script itself

Implication:

- `fast_build_runner` needs a bootstrap strategy compatible with this model

### `build_runner/lib/src/bootstrap/bootstrapper.dart`

Role:

- writes the generated build script
- checks compiled entrypoint freshness through depfiles and digests
- launches the child build process and retries on restart

Important:

- `checkCompileFreshness(...)` is part of normal build-loop behavior
- `isCompileDependency(...)` is used to treat generated entrypoint
  dependencies specially in watch mode
- `run(...)` restarts when the child exits with `ExitCode.tempFail`

Implication:

- fast bootstrap must remain compatible with depfile-based freshness
- compile-dependency events are correctness-sensitive and cannot be treated as
  ordinary source edits

### `build_runner/lib/src/bootstrap/processes.dart`

Role:

- parent/child process communication
- generated build script child entrypoint

Important:

- `ChildProcess.run(...)` is what the generated build script calls
- this is the location where `BuildRunner(..., builderFactories: ...)` starts

Implication:

- we likely need a custom generated entrypoint or custom child runner

### `build_runner/lib/src/commands/watch/watcher.dart`

Role:

- upstream watch loop
- wires watchers to `BuildSeries`

Important:

- it still uses upstream file watching pipeline
- it still debounces internally
- it still calls `BuildSeries.filterChanges(...)`

Implication:

- this is not a good primary base for `fast_build_runner`
- at most it is a reference implementation

### `build_runner/lib/src/build_plan/testing_overrides.dart`

Role:

- test-only customization seam

Important:

- `directoryWatcherFactory` exists
- but it only replaces the watcher implementation
- it does not bypass upstream watch scheduling and filtering stack

Implication:

- custom watcher factory alone is not enough for strong acceleration

### `build_runner/lib/src/io/asset_tracker.dart`

Role:

- filesystem scan-based change detection

Important:

- upstream can compute changes by scanning input sources and generated sources
- this is useful for correctness and recovery

Implication:

- our daemon may outperform it on hot paths
- but we still need a recovery/resync strategy inspired by it

### `build_runner/lib/src/build/resolver/resolvers_impl.dart`

Role:

- owns the shared analysis driver used by builds
- creates `BuildStepResolver` instances

Important:

- initialization is guarded by `Pool(1)`
- analysis-driver access is guarded by `Pool(1)`
- build-level analysis locking is explicit through
  `takeLockAndStartBuild(...)`

Implication:

- builder execution is not free to scale arbitrarily with CPU cores
- fast orchestration can reduce how often resolver-heavy work runs
- it cannot remove analyzer serialization costs once a build is deep in
  semantic resolution

### `build_runner/lib/src/build/resolver/build_step_resolver.dart`

Role:

- per-build-step resolver facade

Important:

- resolving entrypoints within one step is guarded by another `Pool(1)`
- transitive library resolution records resolver entrypoints into
  `InputTracker`

Implication:

- resolver-driven rebuild breadth is tied to what was actually resolved
- fine-grained daemon updates do not replace this tracking

### `build_runner/lib/src/build/build.dart`

Role:

- actual build execution

Important:

- `Build.run(updates)` eventually calls `_updateAssetGraph(...)`
- `_updateAssetGraph(...)` calls `AssetGraph.updateAndInvalidate(...)`
- primary inputs are later discovered through `_matchingPrimaryInputs(...)`
- triggers are still evaluated by `_allowedByTriggers(...)`
- optional phases can run lazily when outputs are requested
- post-process builders run through a separate final phase
- glob nodes are built lazily and can themselves become change sources

Implication:

- custom `updates` influence the build strongly
- but they do not replace internal graph and trigger logic entirely
- lazy and post-process behavior mean build correctness is not reducible to
  "changed files in, builders out"

### `build_runner/lib/src/build/run_builder.dart`

Role:

- executes one builder for many primary inputs

Important:

- inputs are run through `Future.wait(inputs.map(buildForInput))`
- apparent concurrency here is still bounded by resolver locks and shared
  build state

Implication:

- async builder scheduling exists
- but it should not be mistaken for unconstrained parallel semantic analysis

### `build_runner/lib/src/build/asset_graph/graph.dart`

Role:

- asset graph creation and invalidation

Important:

- `updateAndInvalidate(...)` handles:
  - add/modify/remove normalization
  - digest refresh
  - recursive missing-source handling
  - output graph expansion for new sources

Implication:

- our daemon should not try to fully supersede this in early phases
- the first job is to produce better updates entering this machinery

### `build_runner/lib/src/build_plan/phase.dart`

Role:

- defines the runtime model for normal phases, optional phases and
  post-process actions

Important:

- `isOptional` means a phase may never run unless one of its outputs is read
- `hideOutput` changes where outputs may legally live
- post-process actions are represented differently from normal build phases

Implication:

- test coverage must include optional/lazy builders and hidden-output builders
- correctness cannot be validated only on eager source-generating builders

### `build_runner/lib/src/build_plan/build_phases.dart`

Role:

- stores phase identity and builder-options digests
- validates output locations

Important:

- phase identity changes invalidate the build graph
- builder option digests are tracked separately for finer-grained invalidation
- non-hidden output is only allowed for packages in the build

Implication:

- compatibility must include option-change invalidation and hidden-output rules
- workspace/package scope affects legality of outputs

### `build_runner/lib/src/build/single_step_reader_writer.dart`

Role:

- enforces read visibility for each build step
- records inputs and globs read during execution

Important:

- readability depends on phase ordering, generated outputs and package
  visibility
- reads create missing-source nodes when appropriate
- tracked reads feed secondary-input invalidation

Implication:

- daemon-side path knowledge is not enough to predict rebuild scope fully
- build-step reads remain a major source of broad rebuild behavior

### `build_runner/lib/src/io/build_output_reader.dart`

Role:

- exposes the readable output view after a build

Important:

- output visibility depends on whether an output was actually processed
- build dirs / build filters can make a generated file unreadable even if it
  exists in the graph
- failures and deleted outputs are represented explicitly

Implication:

- correctness must include output visibility semantics, not only whether files
  were written
- filtered builds need dedicated compatibility tests

### `build_runner/lib/src/build_plan/build_phase_creator.dart`

Role:

- converts builder definitions, target configs and package graph into concrete
  build phases

Important:

- phase creation depends on builder definitions, target application rules,
  global options, release/dev options and package dependency topology
- strongly connected components of build targets affect phase ordering

Implication:

- `build.yaml` and builder-definition changes are not small local events
- configuration changes can invalidate much more than watcher state

### `build_runner/lib/src/build_plan/build_triggers.dart`

Role:

- builder trigger definitions and parsing

Important:

- upstream supports import and annotation triggers
- triggers are evaluated on parsed compilation units inside build execution

Implication:

- our Rust graph can support preclassification
- but actual trigger semantics remain upstream unless we intentionally mirror
  them

## Viable Integration Seams

### Seam 0: Custom Bootstrap Compatible with Upstream Build Script Model

Assessment:

- `Увер. 10/10`
- `Надёж. 8/10`

This seam is mandatory.

### Seam 1: `BuildPlan.load(...)` + `BuildSeries.run(...)`

Assessment:

- `Увер. 10/10`
- `Надёж. 9/10`

This is the primary seam after bootstrap.

Recommended early usage:

- custom loop drives `BuildSeries.run(...)`
- alpha correctness still reuses `BuildSeries.filterChanges(...)`
- recovery paths may call `BuildSeries.checkForChanges()`

### Seam 2: `Bootstrapper` freshness handling through `BuildPlan` / `BuildSeries`

Assessment:

- `Увер. 9/10`
- `Надёж. 9/10`

We should rely on upstream freshness checks, not duplicate them in Rust.

### Seam 3: `TestingOverrides.directoryWatcherFactory`

Assessment:

- `Увер. 7/10`
- `Надёж. 8/10`

Useful for tests and experiments, but not sufficient as the core production
integration seam.

## Non-Goals Based on Real Code

### Do Not Build v1 Around Upstream `Watcher`

Reason:

- it keeps too much upstream watch pipeline in control

Clarification:

- we should still reuse selective helpers from `BuildSeries`
- the non-goal is upstream `Watcher` as the owning loop, not every upstream
  helper on that path

### Do Not Claim We Replace Invalidation End-to-End

Reason:

- upstream `Build` and `AssetGraph` still own invalidation once updates enter
  the build

### Do Not Promise Trigger Semantics Move to Rust Immediately

Reason:

- upstream trigger evaluation still parses compilation units in Dart

## Corrected Architecture Statement

The accurate architecture is:

1. `fast_build_runner` owns a custom bootstrap path compatible with upstream
   builder-factory generation.
2. Rust daemon improves filesystem event handling and project graph state.
3. Dart adapter inside the builder-capable process converts daemon decisions
   into high-quality `updates`.
4. Early versions may still pass daemon batches through
   `BuildSeries.filterChanges(...)` before `BuildSeries.run(...)`.
5. Upstream `Build` and `AssetGraph` still execute invalidation and build
   scheduling semantics.
6. Optional phases, glob nodes, post-process actions and output visibility
   remain upstream correctness domains that v1 must respect.

This is still a strong acceleration path.
It is just narrower and more realistic than "replace build_runner invalidation
with Rust".

## Realistic LOC Model

### Public Dart CLI

- 400-900 LOC

Includes:

- command parsing
- daemon lifecycle
- logging
- fallback handling
- bootstrap orchestration

### Dart Internal Adapter

- 1,600-3,200 LOC

Includes:

- internal imports
- build session management
- update mapping
- restart/reload handling
- version compatibility guards
- custom child/bootstrap integration

### Rust Daemon Core

- 7,000-12,000 LOC

Includes:

- file watcher backends
- batching
- protocol
- parser
- graph
- persistence

### Benchmarks and Integration Tests

- 2,000-4,000 LOC

## Resulting Forecast

### Strong internal-integration alpha

- 10,000-15,000 LOC total

### Strong internal-integration beta

- 14,000-22,000 LOC total

## Design Consequences for This Repo

The repo should now assume:

- `packages/fast_build_runner_internal` is mandatory
- upstream code references should remain centralized there
- performance claims must be benchmarked against real `BuildSeries` behavior
- bootstrap logic is first-class, not incidental glue
