# Iteration 00: Principles

## Goal

Lock the rules that prevent the project from turning into an uncontrolled
rewrite.

## Decisions

1. Use `build_runner` internal APIs, but isolate them behind a Dart adapter.
2. Keep Rust responsible for hot-path orchestration, not semantic analysis.
3. Target `watch` before `build`.
4. Optimize for measurable wins, not architectural elegance alone.
5. Prefer safe fallback over risky aggressive optimization.

## Practical Rules

- No deep fork of `dart-lang/build` unless proven unavoidable.
- No rewriting `analyzer`.
- No builder API breakage in early phases.
- No public performance claims without fixture-backed numbers.
- No skipping correctness checks just to chase benchmark gains.

## Required Outcomes

- one place where all internal upstream imports live
- one documented compatibility policy
- one benchmark policy used before each milestone

## Done When

- these principles are present in repo docs
- all implementation iterations respect them
