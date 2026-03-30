# Iteration 05: Graph and Invalidation Engine

## Goal

Move from a simple file-event-driven watch loop to a smarter incremental engine
that computes affected files more efficiently.

## Main Outcome

The Rust daemon maintains enough project structure to make better incremental
decisions than raw filesystem events alone.

Correction from real upstream code:

- this iteration reduces noisy or low-value updates before they enter
  `BuildSeries.run(...)`
- it does not replace upstream `AssetGraph.updateAndInvalidate(...)`

## Scope

This iteration should add:

- fast parse of Dart directives
- import/export/part graph
- affected node propagation
- graph persistence

It should not yet attempt:

- full semantic analysis
- custom builder execution planning
- replacement of `analyzer`
- full reimplementation of upstream invalidation semantics

## Why This Is the Performance Core

This iteration contains the logic most likely to produce the strongest gains on
real medium/large projects.

## Tasks

### 1. Build a Fast Directive Parser

Parse only what is needed:

- `import`
- `export`
- `part`
- `part of`

Parser requirements:

- robust with comments/strings
- fast enough for many files
- incremental-friendly

### 2. Build Persistent Import Graph

Represent:

- files
- edges
- reverse edges
- package ownership
- graph revision/version

### 3. Compute Affected Set

Given changed inputs, determine:

- directly changed files
- transitively affected graph slice
- files that are definitely irrelevant

This affected set is first used for:

- suppressing obviously irrelevant updates
- better batching
- better logging/diagnostics

and only later for more aggressive heuristics if benchmark data justifies it.

### 4. Classify Updates

Instead of only "a file changed", classify into buckets:

- definitely relevant
- likely relevant
- configuration-changing
- build-script-affecting
- can-ignore

### 5. Integrate with Dart Adapter

The Dart side should receive richer update context, even if first used only for:

- skip/no-op decisions
- smaller rebuild triggering

It should not initially depend on Rust mirroring every upstream trigger rule.

### 6. Persistence

Store graph state in `.dart_tool/fast_build_runner/`.

Requirements:

- versioned format
- corruption-safe load behavior
- cheap warm startup

## Acceptance Criteria

- graph rebuild works on fixture projects
- one-file changes can be mapped to affected sets
- warm daemon startup reuses graph state
- measured wins exist compared to file-event-only alpha

## Complexity / Risk

- Complexity: `8/10`
- Performance payoff: `10/10`
- Confidence: `7/10`

## Important Note

This iteration is where overengineering can explode.
Do not add semantic-like graph logic unless the benchmark data requires it.
