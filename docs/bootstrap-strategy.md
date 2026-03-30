# Bootstrap Strategy

## Why This Document Exists

After reviewing the real `build_runner` code, the single most important
architecture constraint is:

- an external tool does not directly get runtime `BuilderFactories`
- upstream creates them inside the generated build script entrypoint

This means `fast_build_runner` must solve bootstrap explicitly.

## Upstream Reality

Relevant files in the local upstream clone:

- [build_script_generate.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/bootstrap/build_script_generate.dart)
- [processes.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/bootstrap/processes.dart)
- [build_runner.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_runner.dart)
- [builder_factories.dart](/Users/belief/dev/projects/fast_build_runner/research/dart-build/build_runner/lib/src/build_plan/builder_factories.dart)

The upstream flow is:

1. generate build script source
2. generated script contains actual imports of builder factories
3. generated script constructs runtime `BuilderFactories`
4. generated script calls `ChildProcess.run(args, _builderFactories)`
5. child process runs `BuildRunner(..., builderFactories: ...)`
6. `Bootstrapper` freshness and depfile logic decide when rebuild/restart is
   required

## What This Means for `fast_build_runner`

We cannot rely on this fake-simple model:

- external CLI starts
- external CLI imports `build_runner/src/internal.dart`
- external CLI directly instantiates `BuildPlan`

That is incomplete, because `BuildPlan` usage still needs real
`BuilderFactories`, and those are not directly handed to the external CLI.

## Candidate Strategies

### Option 1: Wrapper Around Standard Upstream Bootstrap

Description:

- let upstream generated script and child process happen normally
- try to hook acceleration around it

Pros:

- smallest bootstrap deviation

Cons:

- too little control
- weak path for strong internal integration
- hard to insert our own session loop where it matters

Assessment:

- `Увер. 6/10`
- `Надёж. 7/10`

### Option 2: Custom Generated Entrypoint Close to Upstream

Description:

- generate our own entrypoint file under `.dart_tool/...`
- keep upstream builder-factory discovery model
- change the generated `main()` so it enters `fast_build_runner_internal`
  instead of directly calling upstream `ChildProcess.run`

Pros:

- preserves the critical builder-factory materialization model
- gives us control over the execution path after bootstrap
- isolates hard coupling into one generator
- stays compatible with depfile-driven script freshness more naturally

Cons:

- tied to upstream build-script generation shape
- must be kept in sync with upstream changes

Assessment:

- `Увер. 9/10`
- `Надёж. 8/10`

### Option 3: Fork Upstream Build Script Generation

Description:

- fully copy upstream build-script generation logic
- modify it however we want

Pros:

- maximum control

Cons:

- higher merge burden
- more upstream drift risk
- easy path into accidental fork

Assessment:

- `Увер. 8/10`
- `Надёж. 5/10`

## Chosen Direction

The recommended strategy is:

### Custom generated entrypoint kept as close as possible to upstream

This means:

- we accept bootstrap coupling
- but we confine it to one subsystem
- and we do not fork the rest of the execution stack

## Practical Design

### Host Side

The public CLI should:

- ensure daemon is running
- generate or refresh fast entrypoint
- compile or launch that entrypoint as needed
- communicate initial process state if needed
- preserve upstream-like restart semantics when the build script changes

### Generated Entrypoint

The generated entrypoint should:

- import real builder factory symbols
- construct runtime `BuilderFactories`
- call a `fast_build_runner_internal` child entrypoint
- stay close enough to upstream layout that depfile freshness and compile
  dependency tracking still make sense

Conceptually:

```dart
Future<void> main(List<String> args) async {
  exitCode = await fastChildProcessRun(args, _builderFactories);
}
```

Not this:

```dart
Future<void> main(List<String> args) async {
  exitCode = await ChildProcess.run(args, _builderFactories);
}
```

### Child Side

The child-side runner should:

- deserialize initial process state if needed
- create fast build session
- coordinate with daemon
- use upstream internal APIs:
  - `BuildPlan.load(...)`
  - `BuildSeries(...)`
  - `BuildSeries.run(...)`
  - optionally `BuildSeries.filterChanges(...)` for alpha correctness

## What Must Stay Close to Upstream

- builder factory discovery
- import generation for build script
- build script freshness assumptions
- parent/child process state handoff model
- entrypoint path conventions where practical

## What We Want to Own

- child-side command loop
- daemon coordination
- update mapping
- fast watch scheduling
- fallback logic

## First Spike Deliverable

The first bootstrap spike should prove exactly this:

1. generate a custom fast build entrypoint
2. compile or launch it
3. obtain runtime `BuilderFactories`
4. run one initial build through our own child-side adapter

If this spike fails, the whole architecture should be re-evaluated early.
