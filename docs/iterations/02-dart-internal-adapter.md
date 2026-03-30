# Iteration 02: Dart Internal Adapter

## Goal

Prove that `fast_build_runner` can drive `build_runner` through internal APIs
without maintaining a full fork.

## Main Outcome

A Dart-only prototype that:

- runs inside a process with real `BuilderFactories`
- loads a `BuildPlan`
- creates a `BuildSeries`
- runs initial and subsequent builds with explicit `updates`
- can bypass the default `Watcher` loop

## Why This Iteration Is Critical

This is the architectural hinge of the entire project.

If this iteration fails, the project likely collapses into either:

- weak wrapper-only acceleration, or
- hard fork territory

This iteration is not a side experiment.
It is the main chosen implementation route.

## Core Upstream Internals to Use

- `package:build_runner/src/internal.dart`
- upstream bootstrap concepts from `build_script_generate.dart` and
  `processes.dart`
- `BuildPlan.load(...)`
- `BuildSeries(...)`
- `BuildSeries.run(...)`
- `BuildPlan.reload()`

Important correction from real code:

- `internal.dart` does not export upstream `Watcher`
- and upstream `Watcher` is not our main target anyway

So the adapter should be built around `BuildPlan` and `BuildSeries`, not
around trying to customize upstream `WatchCommand`.

Additional correction from real code:

- external code does not directly receive runtime `BuilderFactories`
- upstream gets them through generated build script code

So this iteration must prove bootstrap feasibility too, not only build-loop
feasibility.

## Tasks

### 1. Create the Internal Adapter Package

Add a package that explicitly imports:

- `build_runner/src/internal.dart`

This package should have one clear boundary:

- expose stable local adapter methods
- hide upstream internal classes from the rest of the repo

It will likely need both:

- host-side bootstrap orchestration
- child-side build-session entrypoint

### 2. Build an Adapter Facade

Create classes roughly like:

- `FastBuildSession`
- `FastBuildSessionFactory`
- `FastBuildUpdate`
- `FastBuildResult`

The facade should wrap:

- `BuildPlan`
- `BuildSeries`

without leaking them everywhere.

It should also own:

- compatibility checks against supported `build_runner` ranges
- conversion from daemon event batches to `Map<AssetId, ChangeType>`
- config-change and restart-required handling
- bootstrap-aware session creation

### 3. Prove BuilderFactories Bootstrap Path

This is a mandatory proof step.

We need a working strategy to enter a process that has real `BuilderFactories`.

Accepted proof directions:

1. custom generated build entrypoint
2. modified child runner compatible with upstream bootstrap expectations

This proof matters more than cosmetic CLI work.

### 4. Prove Initial Build

Implement path:

- load `BuildPlan`
- call `deleteFilesAndFolders()`
- handle `restartIsNeeded`
- create `BuildSeries`
- run first build with empty updates and `recentlyBootstrapped: true`

### 5. Prove Subsequent Incremental Build

Implement path:

- convert custom updates into `Map<AssetId, ChangeType>`
- in alpha, pass raw daemon changes through `BuildSeries.filterChanges(...)`
  instead of immediately replacing that logic
- call `BuildSeries.run(updates, recentlyBootstrapped: false)`

This is the first proof that a custom update source can control rebuild flow.

Important nuance:

- custom updates control the **entry** into upstream invalidation
- they do not replace `AssetGraph.updateAndInvalidate(...)`
- therefore the adapter must be honest about what is and is not being changed
- reusing `filterChanges(...)` early is a feature, not a failure, because it
  preserves tricky semantics around expected deletes, generated outputs,
  compile dependencies and config files

### 6. Prove Custom Loop Without Upstream Watcher

Do not rely on upstream `Watcher` scheduling.
Build a local loop that:

- receives updates from a mock source
- batches them
- optionally normalizes them through `BuildSeries.filterChanges(...)`
- runs incremental builds
- handles restart-required conditions

Reason from real code:

- upstream `Watcher` still constructs `BuildPackagesWatcher`
- still debounces internally
- still calls `BuildSeries.filterChanges(...)`
- therefore it preserves too much of the default hot path

Clarification:

- the non-goal is upstream `Watcher` as the owner of the loop
- `BuildSeries.filterChanges(...)` and `checkForChanges()` remain valid helper
  seams for alpha correctness and recovery

### 7. Add Safe Fallback

If the internal adapter detects unsupported conditions, it should:

- exit with clear diagnostics, or
- delegate to normal `build_runner`

Unsupported means, for example:

- incompatible `build_runner` version
- internal API import breakage
- unsupported command mode

## Output of This Iteration

At the end of this iteration we need a demo like:

1. Enter custom bootstrap path
2. Start fast session
3. Perform initial build
4. Inject one changed file
5. Observe successful incremental rebuild

Bonus proof if available:

6. Trigger a `build.yaml` change and verify `BuildPlan.reload()` / restart path

## Acceptance Criteria

- bootstrap path with real builder factories is proven
- initial build works on a small fixture
- follow-up build with manual updates works
- no deep fork of upstream code exists
- all internal imports are isolated to one local package

## Complexity / Risk

- Complexity: `7/10`
- Architectural importance: `10/10`
- Confidence: `8/10`

## Likely Failure Modes

- internal API shape forces too much coupling
- update semantics are not enough without more upstream behavior
- resolver serialization means the measured win is smaller than expected
- reload / restart handling is more complex than expected
- daemon-provided updates are too noisy to beat upstream filtering meaningfully
- builder-factory bootstrap requires more upstream mirroring than desired

## If Blocked

Fallback exploration options:

1. Use more internal classes but still keep them isolated. `Увер. 8/10`, `Надёж. 8/10`
2. Patch one tiny upstream hook instead of forking core flow. `Увер. 7/10`, `Надёж. 8/10`
3. Downgrade to wrapper-only mode temporarily. `Увер. 9/10`, `Надёж. 9/10`
