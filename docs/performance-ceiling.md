# Performance Ceiling

## Purpose

This document records the strongest performance ceilings found in the real
`build_runner` code so that `fast_build_runner` does not over-promise.

The project is still worth doing.
But the upside is bounded by specific upstream behavior.

## Executive Summary

The best honest statement is:

> `fast_build_runner` can strongly improve the path that decides whether and
> when a build starts, and how noisy file changes are normalized, but it does
> not remove the cost of analyzer-heavy builder execution once that execution
> begins.

Assessment:

- `Увер. 10/10`
- `Надёж. 9/10`

## Ceiling 1: Resolver Access Is Serialized

Files:

- [resolvers_impl.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/resolver/resolvers_impl.dart)
- [build_step_resolver.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/resolver/build_step_resolver.dart)

Why it matters:

- `ResolversImpl` guards initialization with `Pool(1)`
- `ResolversImpl` guards analysis-driver access with `Pool(1)`
- `BuildStepResolver` guards per-step entrypoint resolution with `Pool(1)`

Practical consequence:

- analyzer-heavy builders retain a serialization bottleneck
- more CPU cores do not automatically convert into proportional build speedup

## Ceiling 2: Secondary Reads Drive Rebuild Breadth

Files:

- [input_tracker.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/input_tracker.dart)
- [single_step_reader_writer.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/single_step_reader_writer.dart)
- [build.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/build.dart)

Why it matters:

- build steps record what they read
- resolver entrypoints and file reads become part of future invalidation
- broad semantic reads can cause broad future rebuilds

Practical consequence:

- a faster watcher cannot by itself fix builders that read too widely

## Ceiling 3: Upstream Owns Invalidation Once Build Starts

Files:

- [build.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/build.dart)
- [graph.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/asset_graph/graph.dart)

Why it matters:

- `BuildSeries.run(...)` feeds updates into upstream `Build`
- `Build` then calls `_updateAssetGraph(...)`
- `_updateAssetGraph(...)` then calls `AssetGraph.updateAndInvalidate(...)`

Practical consequence:

- the daemon improves the quality of the input to invalidation
- it does not replace invalidation ownership end to end

## Ceiling 4: Config Changes Are Large-Scope Events

Files:

- [build_plan.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/build_plan.dart)
- [build_phase_creator.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/build_phase_creator.dart)

Why it matters:

- `build.yaml`, builder definitions, global options and package topology all
  affect phase creation
- config changes may invalidate the build script and asset graph together

Practical consequence:

- config edits are restart/reload events, not ordinary hot-path updates

## Ceiling 5: Lazy and Post-Process Semantics Limit How Aggressively We Can Simplify

Files:

- [phase.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/phase.dart)
- [build.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/build.dart)
- [build_output_reader.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/io/build_output_reader.dart)

Why it matters:

- optional builders may never run until an output is requested
- glob nodes can become their own change source
- post-process steps have separate run conditions
- readable output after a build depends on more than whether files were written

Practical consequence:

- the fast path can accelerate scheduling, but it should not flatten upstream
  semantics into a naive eager execution model

## Ceiling 6: Bootstrap Freshness Is Part of the Fast Path

Files:

- [bootstrapper.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/bootstrap/bootstrapper.dart)
- [build_series.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/build_series.dart)

Why it matters:

- build-script freshness is checked during normal execution
- compile dependencies of the generated entrypoint are watched specially

Practical consequence:

- fast watch mode must stay compatible with bootstrap freshness behavior
- a custom loop cannot treat these files like ordinary source edits

## Best-Case vs Bounded Cases

### Best cases

- no-op or near-no-op rebuilds
- small source edits that should not cause wide semantic reads
- noisy filesystem scenarios where better batching matters

Assessment:

- `Увер. 9/10`
- `Надёж. 9/10`

### Bounded cases

- builders that call deeply into `analyzer`
- projects with broad resolver entrypoints and dense import/export graphs
- changes that hit config, build script or workspace shape

Assessment:

- `Увер. 10/10`
- `Надёж. 9/10`

## Honest Product Claim

The honest claim for the project is:

- `watch` should feel materially faster
- no-op and tiny incremental builds should improve the most
- analyzer-heavy worst cases should improve less
- clean builds should improve the least
