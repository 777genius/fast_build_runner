# Feasibility Assessment

## Purpose

This document answers the practical question:

> Is the `fast_build_runner` idea real after reading the actual
> `build_runner` source code?

Short answer:

- **yes, the idea is real**
- **but narrower than the naive first impression**
- **and bootstrap is a first-class problem**

## Executive Verdict

### Main Verdict

Building a meaningful accelerator around `build_runner` is feasible.

Assessment:

- `Увер. 9/10`
- `Надёж. 8/10`

### Why It Is Feasible

- `build_runner` has a real internal execution seam at
  `BuildPlan.load(...)` + `BuildSeries.run(...)`
- updates are passed explicitly into the build pipeline
- the watch loop is separable from the build execution loop
- upstream keeps substantial state in process, which favors a long-lived
  optimized controller

### Why It Is Harder Than It First Looked

- runtime `BuilderFactories` are created in the generated build script
- build-script freshness and restart handling are integral to normal operation
- upstream invalidation remains in control once updates enter `Build`
- broad rebuild behavior is often caused by secondary-input tracking and
  builder semantics, not only watcher overhead
- resolver-heavy execution is partially serialized by upstream pools, so build
  concurrency has a real ceiling

## What We Can Realistically Improve

### 1. Hot Watch Path

Assessment:

- `Увер. 9/10`
- `Надёж. 9/10`

We can realistically improve:

- file event handling
- batching
- path normalization
- update noise reduction
- warm long-lived state
- scheduling around `BuildSeries.run(...)`
- early correctness by still reusing `BuildSeries.filterChanges(...)`

This is the strongest part of the idea.

### 2. No-Op / Tiny Incremental Builds

Assessment:

- `Увер. 9/10`
- `Надёж. 8/10`

This is also very realistic, because a lot of avoidable cost is in:

- event handling
- filesystem scans
- process path overhead
- unnecessary incremental loop work
- avoiding needless rebuild entry in the first place

### 3. Repeated Build Startup

Assessment:

- `Увер. 8/10`
- `Надёж. 8/10`

Possible, but only after bootstrap is handled carefully.

### 4. Analyzer-Heavy Worst Cases

Assessment:

- `Увер. 7/10`
- `Надёж. 7/10`

The idea still helps, but much less dramatically.
Once a builder is deep inside analyzer-heavy resolution and secondary-input
tracking, our daemon cannot magically erase that cost.

### 5. Alpha Strategy Can Reuse Upstream Filtering Without Reusing Upstream Watcher

Assessment:

- `Увер. 10/10`
- `Надёж. 9/10`

After re-reading the real watch path, an important correction is:

- we should not base the product on upstream `Watcher`
- but we should strongly consider reusing `BuildSeries.filterChanges(...)`
  in alpha
- and `BuildSeries.checkForChanges()` as a recovery/resync mechanism

This reduces correctness risk without giving up the custom daemon-owned loop.

### 6. Performance Ceiling Is Real and Visible in Code

Assessment:

- `Увер. 10/10`
- `Надёж. 9/10`

The code shows several ceilings that bound our upside:

- `ResolversImpl` guards initialization and driver access with `Pool(1)`
- `BuildStepResolver` guards per-step entrypoint resolution with `Pool(1)`
- `InputTracker` and `SingleStepReaderWriter` make secondary reads part of
  rebuild semantics
- `BuildPhaseCreator` means config changes can invalidate large parts of the
  plan, not just watch state
- optional phases, glob nodes and post-process steps add correctness cases that
  are not captured by a simple changed-file model

## What We Cannot Honestly Claim

### We Cannot Claim to Replace Upstream Invalidation

Assessment:

- `Увер. 10/10`
- `Надёж. 10/10`

Reason:

- `BuildSeries.run(...)` feeds updates into upstream `Build`
- upstream `Build` calls `_updateAssetGraph(...)`
- upstream `AssetGraph.updateAndInvalidate(...)` still owns graph mutation

### We Cannot Claim to Eliminate Broad Rebuilds Universally

Assessment:

- `Увер. 10/10`
- `Надёж. 9/10`

Reason:

- builders track secondary inputs
- resolver paths and trigger paths stay upstream
- project import topology still matters

### We Cannot Claim to Remove Analyzer Serialization Costs

Assessment:

- `Увер. 10/10`
- `Надёж. 10/10`

Reason:

- upstream analysis access is deliberately serialized in several places
- `runBuilder(...)` can schedule async work, but semantic resolution still
  funnels through shared locks

### We Cannot Claim Bootstrap Is Easy

Assessment:

- `Увер. 10/10`
- `Надёж. 10/10`

Reason:

- real `BuilderFactories` are materialized in generated build script code
- external tools do not receive them directly

## Most Important Upstream Realities

### BuilderFactories Bootstrap

Files:

- [build_script_generate.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/bootstrap/build_script_generate.dart)
- [processes.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/bootstrap/processes.dart)

Meaning:

- a custom bootstrap path is mandatory

### Main Execution Seam

Files:

- [build_plan.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/build_plan.dart)
- [build_series.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/build_series.dart)

Meaning:

- this is the real seam worth building around

### Upstream Watcher Is Not the Main Base

File:

- [watcher.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/commands/watch/watcher.dart)

Meaning:

- replacing only the watcher factory is not enough for the intended result

### Secondary Inputs Matter a Lot

Files:

- [input_tracker.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/input_tracker.dart)
- [single_step_reader_writer.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/single_step_reader_writer.dart)

Meaning:

- many expensive rebuilds are tied to what builders read, not just what files
  changed on disk

### Resolver Concurrency Is Intentionally Limited

Files:

- [resolvers_impl.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/resolver/resolvers_impl.dart)
- [build_step_resolver.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/resolver/build_step_resolver.dart)
- [run_builder.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/run_builder.dart)

Meaning:

- async builder scheduling exists
- but access to the analysis driver is deliberately serialized
- this caps the upside of any orchestration-only rewrite

### Phase Creation Is a Real Config Boundary

Files:

- [build_phase_creator.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/build_phase_creator.dart)
- [build_plan.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/build_plan.dart)

Meaning:

- builder definitions, target configs, workspace shape and global options all
  affect phase creation
- config changes are larger than simple watch updates

### Optional / Lazy / Post-Process Semantics Are First-Class

Files:

- [phase.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/phase.dart)
- [build.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/build.dart)
- [build_output_reader.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/io/build_output_reader.dart)

Meaning:

- not every relevant action runs eagerly
- some outputs only exist when lazily requested
- post-process actions and output visibility have separate semantics

## Realistic Expected Wins

### Best Case

- no-op build: 2x-5x
- tiny incremental: 1.5x-3x

Assessment:

- `Увер. 8/10`
- `Надёж. 8/10`

### Typical Medium App

- incremental: 1.2x-2x

Assessment:

- `Увер. 8/10`
- `Надёж. 8/10`

### Analyzer-Heavy / Broad Secondary-Input Case

- incremental: 1.1x-1.7x

Assessment:

- `Увер. 7/10`
- `Надёж. 7/10`

## Strongest Honest v1 Shape

The strongest honest v1 is now:

1. custom bootstrap compatible with upstream generated entrypoint
2. daemon-owned watch loop and batching
3. Dart internal adapter around `BuildPlan` and `BuildSeries`
4. reuse `BuildSeries.filterChanges(...)` in alpha for correctness
5. optional recovery with `BuildSeries.checkForChanges()`
6. let upstream `Build` and `AssetGraph` keep invalidation ownership
7. explicitly validate optional builders, glob inputs and post-process cases in
   the test matrix

Assessment:

- `Увер. 10/10`
- `Надёж. 9/10`

## Strongest Reasons the Project Could Fail

1. Bootstrap path becomes too coupled to upstream generated script details.  
   `Увер. 9/10`, `Надёж. 8/10`

2. The measurable gains are too small on real community projects outside the
   ideal hot-path cases.  
   `Увер. 8/10`, `Надёж. 8/10`

3. Maintaining compatibility across upstream updates becomes noisier than
   expected.  
   `Увер. 8/10`, `Надёж. 8/10`

## Strongest Reasons the Project Could Succeed

1. The chosen seam is real and not hypothetical.  
   `Увер. 10/10`, `Надёж. 9/10`

2. Watch-mode pain is real and highly visible to users.  
   `Увер. 9/10`, `Надёж. 9/10`

3. The design does not require replacing builders or analyzer.  
   `Увер. 9/10`, `Надёж. 9/10`

## Final Assessment

The idea is real enough to build.

But the honest form of the idea is:

> custom bootstrap + Rust daemon + Dart internal adapter around
> `BuildPlan`/`BuildSeries`, with upstream still owning actual build execution
> and invalidation semantics.

That is a strong project.
It is just not a trivial wrapper, and not a magical invalidation rewrite.
