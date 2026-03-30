# Edge Cases

## Purpose

This document records the most important edge cases discovered from reading the
real `build_runner` code.

These are not hypothetical. They are implementation constraints.

## 1. BuilderFactories Are Not Directly Available

Severity:

- critical

Files:

- [build_script_generate.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/bootstrap/build_script_generate.dart)
- [processes.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/bootstrap/processes.dart)

Why it matters:

- the external CLI cannot simply instantiate `BuildPlan` directly unless it is
  already inside a builder-capable process

Implementation consequence:

- bootstrap must be solved first

## 2. Build Script Freshness Can Force Restart

Severity:

- critical

Files:

- [bootstrapper.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/bootstrap/bootstrapper.dart)
- [build_series.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/build_series.dart)

Why it matters:

- a build may need to restart because the build script changed
- this is normal behavior, not an exceptional edge case

Implementation consequence:

- fast path must handle restart-required results cleanly

## 3. `build.yaml` Changes Force Reload Path

Severity:

- high

Files:

- [build_series.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/build_series.dart)
- [build_plan.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/build_plan.dart)

Why it matters:

- config changes can invalidate build phases and builder availability

Implementation consequence:

- daemon update classification must detect config-path changes specially

## 4. Upstream `Watcher` Still Does Too Much

Severity:

- high

File:

- [watcher.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/commands/watch/watcher.dart)

Why it matters:

- even with a custom watcher factory, upstream still performs debouncing,
  merging and `filterChanges(...)`

Implementation consequence:

- not a good base for the main fast path
- but this does **not** mean we should throw away every helper on that path

## 5. Bypassing `Watcher` Means We Must Deliberately Preserve Filtering Semantics

Severity:

- critical

Files:

- [watcher.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/commands/watch/watcher.dart)
- [build_series.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/build_series.dart)
- [bootstrapper.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/bootstrap/bootstrapper.dart)

Why it matters:

- upstream watch mode does not pass raw filesystem events straight to builds
- it uses `expectedDeletes`, `filterChanges(...)`, debounce and compile
  dependency handling
- `filterChanges(...)` suppresses generated-output noise, expected deletes,
  `.dart_tool/build` noise and content-identical modifications

Implementation consequence:

- a custom loop should likely reuse `BuildSeries.filterChanges(...)` in alpha
- otherwise we risk regressing correctness while trying to optimize

## 6. Secondary Inputs Cause Broad Rebuilds

Severity:

- critical

Files:

- [input_tracker.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/input_tracker.dart)
- [single_step_reader_writer.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/single_step_reader_writer.dart)

Why it matters:

- builders track files they read
- resolver activity and reads become part of rebuild semantics

Implementation consequence:

- even perfect filesystem watching cannot erase all broad rebuild costs

## 7. Resolver Access Is Intentionally Serialized

Severity:

- critical

Files:

- [resolvers_impl.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/resolver/resolvers_impl.dart)
- [build_step_resolver.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/resolver/build_step_resolver.dart)
- [run_builder.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/run_builder.dart)

Why it matters:

- upstream uses `Pool(1)` both for resolver initialization and driver access
- per-build-step entrypoint resolution is also serialized
- async scheduling in `runBuilder(...)` does not mean unlimited semantic
  parallelism

Implementation consequence:

- daemon wins will be strongest before resolver-heavy execution starts
- we should not over-promise improvements for analyzer-dominated workloads

## 8. Trigger Semantics Stay Upstream Initially

Severity:

- medium-high

Files:

- [build_triggers.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/build_triggers.dart)
- [build.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/build.dart)

Why it matters:

- triggers are evaluated inside build execution using parsed compilation units

Implementation consequence:

- Rust can help preclassify, but should not initially claim semantic parity

## 9. Workspace Mode Is Not Just “More Packages”

Severity:

- high

Files:

- [build_packages.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/build_packages.dart)
- [build_packages_loader.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/build_packages_loader.dart)

Why it matters:

- workspace root, output root and watched package sets differ by mode
- single-package-in-workspace is a separate behavior mode

Implementation consequence:

- path mapping and output-root logic must be tested in workspace scenarios

## 10. Fixed Packages Are Not Watched

Severity:

- medium

File:

- [build_packages_loader.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/build_packages_loader.dart)

Why it matters:

- hosted/git/sdk packages are treated as fixed and not watched for file changes

Implementation consequence:

- daemon must mirror or consciously adapt this policy

## 11. Visibility Rules Differ for Root vs Dependency Packages

Severity:

- medium-high

File:

- [build_configs.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/build_configs.dart)

Why it matters:

- not every asset in every package is visible in the build

Implementation consequence:

- path-to-`AssetId` mapping is not enough; build visibility matters too

## 12. Generated Output Noise Must Be Suppressed Carefully

Severity:

- high

Files:

- [build_series.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/build_series.dart)
- [node.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/asset_graph/node.dart)

Why it matters:

- generated output modifications are often ignored
- deletes have special meaning
- missing sources remain represented in the graph

Implementation consequence:

- daemon event normalization must not treat all file events equally

## 13. Build-Phase Recreation Is a Large-Scale Config Boundary

Severity:

- high

Files:

- [build_phase_creator.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/build_phase_creator.dart)
- [build_plan.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/build_plan.dart)

Why it matters:

- phase creation depends on builder definitions, target configs, global
  options, release/dev options and package dependency topology
- `build.yaml` changes are not a tiny local watch event

Implementation consequence:

- config changes should stay on an upstream reload/restart path
- Rust should not attempt to own phase recreation early

## 14. Build Dirs and Build Filters Affect Primary Inputs

Severity:

- medium

File:

- [build_dirs.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/build_dirs.dart)

Why it matters:

- build selection is affected by build dirs / filters / public asset rules

Implementation consequence:

- benchmark and CLI behavior must test filtered builds too

## 15. Compile Dependencies of the Generated Entrypoint Are Special

Severity:

- high

Files:

- [bootstrapper.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/bootstrap/bootstrapper.dart)
- [build_series.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/build_series.dart)

Why it matters:

- upstream tracks whether a changed path is a dependency of the compiled
  entrypoint script
- watch-mode filtering treats compile dependencies specially because they can
  force build-script refresh or restart

Implementation consequence:

- daemon path classification must not collapse these into ordinary source edits
- bootstrap freshness remains part of the fast path

## 16. Parent Process Does Not Run Work in Parallel with Child

Severity:

- medium

File:

- [processes.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/bootstrap/processes.dart)

Why it matters:

- upstream parent waits for child; there is no hidden parallel overlap

Implementation consequence:

- if we want concurrency benefits, we need to design them explicitly around our
  daemon and bootstrap flow

## 17. Output Root and Cache Paths Matter

Severity:

- medium

Files:

- [constants.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/constants.dart)
- [build_packages.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/build_packages.dart)

Why it matters:

- `.dart_tool/build` and entrypoint paths are special
- output root differs between single-package and workspace builds

Implementation consequence:

- daemon path normalization must preserve output-root semantics

## 18. Optional Phases Run Lazily, Not Eagerly

Severity:

- critical

Files:

- [phase.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/phase.dart)
- [build.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/build.dart)

Why it matters:

- some builders do not run during the main eager phase scan
- they only run if one of their outputs is read later by another build step or
  becomes a needed primary input
- `Build` tracks these through `lazyPhases`

Implementation consequence:

- v1 cannot assume that "all relevant builders ran during the main loop"
- compatibility tests must include optional builders and lazy output reads

## 19. Glob Nodes Are Their Own Rebuild Surface

Severity:

- high

Files:

- [build.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/build.dart)
- [node.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/asset_graph/node.dart)

Why it matters:

- glob nodes are tracked in the asset graph
- they are built lazily
- they can change when generated inputs appear, disappear or stop being output

Implementation consequence:

- changed-file logic alone is not enough to reason about rebuild breadth
- fixtures should include builders that use `findAssets` / glob inputs

## 20. Post-Process Builders Follow Different Semantics

Severity:

- high

Files:

- [phase.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/phase.dart)
- [build.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/build.dart)
- [build_phases.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/build_phases.dart)

Why it matters:

- post-process builders run in a dedicated final phase
- they operate on post-process step ids, not the normal in-build phase model
- they may add outputs or mark the primary input as deleted

Implementation consequence:

- v1 compatibility claims must explicitly include or exclude post-process
  builders
- they should not be treated as a trivial extension of normal builder runs

## 21. Output Visibility Depends on More Than "File Exists"

Severity:

- high

Files:

- [build_output_reader.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/io/build_output_reader.dart)
- [build_dirs.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build/build_dirs.dart)

Why it matters:

- a generated file may exist in the graph but still be unreadable
- build dirs and build filters can suppress outputs from the readable result
- failed, deleted and not-output states are distinct

Implementation consequence:

- correctness checks must inspect output visibility semantics, not only disk
  writes
- filtered-build support needs explicit tests

## 22. Hidden-Output Rules Restrict Builders on Dependency Packages

Severity:

- medium-high

Files:

- [build_phase_creator.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/build_phase_creator.dart)
- [build_phases.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/build_phases.dart)

Why it matters:

- builders targeting non-output packages are only legal with hidden output
- this rule also applies through applied builders

Implementation consequence:

- workspace and dependency-package fixtures must include hidden-output cases
- path mapping alone does not guarantee an action is legal

## 14. Existing `build_runner` Already Has a `daemon` Command

Severity:

- low-medium

Why it matters:

- naming and logs must not confuse our daemon with upstream daemon-related
  functionality

Implementation consequence:

- docs and CLI wording should explicitly say “fast_build_runner daemon” or just
  keep it internal
