# Public Demo

This document is the shortest honest path to showing `fast_build_runner`
publicly.

## What To Say

Use this framing:

- this is **not** a full `build_runner` replacement
- this is a **custom bootstrap + custom watch runtime** experiment
- builders and analyzer still stay in Dart
- Rust currently improves the **source engine / watch ingestion path**
- the current fixture is tiny, so total wall-clock is still heavily dominated by upstream initial build cost
- the more interesting signal right now is often the **incremental build timing**, not only total elapsed time

## Commands

Run from the repo root.

### 1. Prove the bootstrap seam

```bash
/Users/belief/dev/flutter/bin/dart run bin/fast_build_runner.dart spike-bootstrap
```

Expected:

- status `success`
- real generated outputs
- initial and incremental build entries present

### 2. Prove custom watch runtime on Dart source engine

```bash
/Users/belief/dev/flutter/bin/dart run bin/fast_build_runner.dart spike-watch \
  --source-engine=dart \
  --incremental-cycles=2
```

Expected:

- status `success`
- `incrementalBuilds` contains multiple entries
- `mergedUpdateBatches` shows a narrowed single-asset update

### 3. Prove Rust source engine integration

```bash
/Users/belief/dev/flutter/bin/dart run bin/fast_build_runner.dart spike-watch \
  --source-engine=rust \
  --incremental-cycles=2
```

Expected:

- status `success`
- warnings include Rust source engine usage
- watch path still flows through the same custom runtime

### 4. Show benchmark summary

```bash
/Users/belief/dev/flutter/bin/dart run bin/fast_build_runner.dart benchmark-watch \
  --output=summary
```

Expected interesting fields:

- `dart`
- `rust`
- `dartInitialBuild`
- `rustInitialBuild`
- `dartIncrementalBuild`
- `rustIncrementalBuild`
- `rustInitialBuildSpeedupVsDart`
- `rustIncrementalBuildSpeedupVsDart`
- `rustSpeedupVsDart`

### 5. Produce markdown for a post or gist

```bash
/Users/belief/dev/flutter/bin/dart run bin/fast_build_runner.dart benchmark-watch \
  --output=markdown
```

## What Not To Overclaim

Do not claim:

- “Rust makes `build_runner` universally faster”
- “this already replaces `build_runner watch`”
- “these numbers generalize to large real apps”
- “the Rust daemon already owns invalidation semantics”

Do say:

- “the bootstrap seam is working”
- “the custom runtime is working”
- “Rust is already integrated as an alternative source engine”
- “the benchmark output now separates total time from incremental build timing”

## Strongest Current Demo Angles

Top 3:

1. **Custom runtime over real upstream `BuilderFactories`**. `Увер. 10/10`, `Надёж. 9/10`
2. **Rust daemon integrated into the watch source path without deep forking upstream**. `Увер. 9/10`, `Надёж. 8/10`
3. **Benchmark output is now honest enough to discuss total vs incremental timing separately**. `Увер. 9/10`, `Надёж. 8/10`

## Best One-Paragraph Public Summary

`fast_build_runner` is an experiment in accelerating the incremental path of
`build_runner` without rewriting the Dart build ecosystem. It already has a
custom bootstrap path with real upstream builder factories, a custom watch
runtime around `BuildPlan` and `BuildSeries`, and an optional Rust-backed
source engine for watch ingestion. The current tiny fixture still makes total
wall-clock noisy, but the tool now reports initial and incremental timing
separately so the effect of the watch/source-engine path can be discussed more
honestly.
