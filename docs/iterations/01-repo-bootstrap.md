# Iteration 01: Repository Bootstrap

## Goal

Create the repository structure and tooling baseline so implementation can
proceed without reshaping the repo every few days.

## Main Outcome

A repository with:

- Dart workspace/packages for CLI and integration code
- Rust crate for the daemon
- shared protocol definitions strategy
- benchmark fixtures layout
- scripts and CI skeleton

## Deliverables

- `pubspec.yaml` workspace or package structure
- `packages/fast_build_runner`
- `packages/fast_build_runner_internal`
- `packages/fast_build_runner_bench`
- `native/daemon`
- `fixtures/`
- `scripts/`
- root docs and contributor notes
- bootstrap strategy notes and spike files

## Why This Iteration Exists

Without an explicit structure, the project will blur together:

- product CLI
- unstable internal integration code
- benchmarks
- daemon internals

That will slow down every later iteration.

## Tasks

### 1. Choose Workspace Layout

Preferred layout:

```text
packages/
  fast_build_runner/
  fast_build_runner_internal/
  fast_build_runner_bench/
native/
  daemon/
fixtures/
scripts/
```

Reason:

- keeps public CLI separate from unstable adapter code
- allows testing internal integration without polluting user package

### 2. Create Root Repository Metadata

Add:

- root `README.md`
- root `.gitignore`
- root CI placeholders
- root contributing notes later if needed

### 3. Create Public Dart Package

`packages/fast_build_runner` should own:

- command-line parsing
- user-facing configuration
- logging and diagnostics
- fallback behavior
- daemon lifecycle management from Dart side

It should *not* own fragile upstream integration details.

It should own:

- user-facing bootstrap orchestration
- deciding when to run normal `build_runner` vs fast path

### 4. Create Internal Dart Package

`packages/fast_build_runner_internal` should own:

- imports from `build_runner/src/internal.dart`
- wrappers around `BuildPlan`
- wrappers around `BuildSeries`
- compatibility gates by version
- adaptation between daemon updates and `build_runner`
- bootstrap entrypoint logic for the builder-capable child process

This package exists to contain breakage when upstream internals shift.

### 5. Create Benchmark Package

`packages/fast_build_runner_bench` should own:

- benchmark runner
- fixture preparation
- before/after comparison scripts
- reporting

### 6. Create Rust Daemon Crate

`native/daemon` should own:

- file watcher backend
- graph engine
- parser
- persistence
- IPC server

### 7. Decide Protocol Ownership

Pick one of these:

1. JSON protocol with manual structs in both languages
2. generated schema approach
3. line-delimited JSON for alpha, stronger protocol later

Recommended first choice:

- line-delimited JSON over stdio or local socket

Reason:

- fast to debug
- easy to capture in logs
- minimal tooling overhead

### 8. Decide Bootstrap Strategy

This is mandatory in this iteration.

Candidate directions:

1. custom generated entrypoint that calls our child runner
2. generated upstream script plus replacement child-run target
3. forked build-script template with minimal divergence

Recommended first direction:

1. custom generated entrypoint that stays as close as possible to upstream

Reason:

- builder factories are only available inside generated build script code
- this keeps hard coupling localized

## Acceptance Criteria

- repo structure exists
- packages compile as shells
- daemon crate compiles as shell
- benchmark package can run a placeholder command
- bootstrap approach is documented explicitly

## Time / Complexity

- Complexity: `4/10`
- Value: `8/10`
- Implementation confidence: `9/10`

## Notes

Do not overengineer the protocol or CI in this iteration.
The purpose is to create stable boundaries, not full functionality.
