# Iteration 07: Build Mode and AOT Expansion

## Goal

Extend the watch-first architecture into repeated `build` mode and add startup
optimizations where they meaningfully help.

## Main Outcome

Support:

- `fast_build_runner build`
- daemon reuse across invocations
- AOT/JIT policy decisions
- improved repeated build startup

## Why This Is Not First

`watch` is where the strongest user pain and clearest wins exist.
This iteration should happen after the project has already proven itself in the
incremental path.

## Tasks

### 1. Build Command Integration

Implement:

- public `build` command
- session startup
- optional daemon reuse
- one-shot execution semantics

### 2. Warm State Reuse

Allow repeated build invocations to reuse:

- graph snapshots
- daemon session state where safe
- cached environment metadata

### 3. AOT/JIT Decision Layer

Add a policy that decides:

- when to use `--force-aot`
- when to remain on JIT
- how to fallback cleanly

### 4. Public Diagnostics

Expose:

- why AOT was chosen
- why fallback happened
- whether warm state was reused

### 5. Measure Startup Benefit

This iteration must prove that added complexity is justified.

## Acceptance Criteria

- repeated `build` command works
- daemon reuse is safe
- AOT fallback is stable
- benchmark evidence shows real startup benefit

## Complexity / Risk

- Complexity: `7/10`
- User value: `7/10`
- Confidence: `8/10`

## Important Rule

Do not let AOT logic spread through the whole codebase.
Keep it in one policy layer so that rollback is cheap if it underdelivers.
