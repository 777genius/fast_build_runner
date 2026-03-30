# Iteration 04: Fast Watch Pipeline

## Goal

Combine the Dart internal adapter and Rust daemon into the first end-to-end
accelerated `watch` command.

## Main Outcome

A working `fast_build_runner watch` command that:

- enters the custom bootstrap path
- performs initial build
- listens for daemon update batches
- converts batches to `AssetId -> ChangeType`
- drives `BuildSeries.run(...)`
- falls back safely when needed

This is the first public slice of the chosen internal-integration strategy,
not an optional intermediate branch.

## Why This Iteration Is the First Real Product Milestone

This is the first point where users can feel performance changes.

## Detailed Flow

1. CLI parses user command
2. CLI resolves supported mode and version range
3. CLI starts or connects to daemon
4. CLI enters custom bootstrap entrypoint
5. Dart adapter creates build session
6. initial build runs
7. daemon emits batched updates
8. Dart adapter transforms updates
9. alpha path optionally normalizes them with `BuildSeries.filterChanges(...)`
10. build session runs incremental build
11. results are logged and loop continues

More precise real-code flow:

7. daemon emits batched updates
8. Dart adapter transforms them into `Map<AssetId, ChangeType>`
9. alpha path may first run `BuildSeries.filterChanges(...)`
10. `BuildSeries.run(...)` receives the update map
11. upstream `Build` calls `_updateAssetGraph(...)`
12. upstream `AssetGraph.updateAndInvalidate(...)` runs
13. upstream build phases execute

## Tasks

### 1. Implement Public CLI Command

Add:

- `fast_build_runner watch`

Initial flags:

- verbosity
- fallback mode
- daemon log mode
- benchmark trace mode

The command must also control the bootstrap mode used to reach
builder-capable execution.

### 2. Connect Daemon Batches to Build Updates

This is the first place where careful mapping matters:

- daemon path -> package name
- path -> `AssetId`
- filesystem event -> `ChangeType`

Also required:

- distinguish source edits from generated output noise
- preserve add/remove semantics for missing-source behavior
- avoid sending synthetic updates that conflict with upstream graph state
- preserve compile-dependency and expected-delete behavior

### 3. Rebuild Scheduling

Implement a simple scheduling model:

- one build at a time
- batch incoming changes while build is running
- merge batches after completion
- keep an escape hatch for full resync via `BuildSeries.checkForChanges()`

### 4. Restart / Reload Handling

The integration must correctly handle:

- build config changes
- build script invalidation
- restart-required results

From real upstream code this specifically means:

- `BuildSeries.run(...)` may return `BuildResult.buildScriptChanged()`
- config updates trigger `BuildPlan.reload()`
- bootstrapper freshness checks still happen on non-initial builds
- compile-dependency changes can force the same restart path

### 5. Fallback Logic

If conditions become unsupported:

- print reason
- optionally switch to regular `build_runner watch`

Examples:

- unsupported `build_runner` version
- build script restart loops
- daemon state corruption
- path mapping mismatch
- unsupported workspace/output-root shape

### 6. Logging

User-facing logs should clearly show:

- daemon connected or started
- initial build phase
- update batches received
- build times
- fallback events

## Acceptance Criteria

- can watch a small fixture continuously
- rebuilds happen from daemon-driven updates
- build script changes are handled safely
- fallback works and is visible

## Metrics to Capture

- time from save to rebuild start
- time from save to rebuild completion
- batch sizes
- number of updates dropped/merged
- number of resyncs that required `checkForChanges()`

## Complexity / Risk

- Complexity: `7/10`
- User value: `10/10`
- Confidence: `8/10`
