# Iteration 06: Benchmarks and Compatibility

## Goal

Build the evidence base that proves the project is useful and safe enough for
external users.

## Main Outcome

A benchmark and compatibility program that catches:

- performance regressions
- upstream compatibility breakage
- incorrect output behavior

## Why This Iteration Is Mandatory

Without this iteration, the project risks becoming:

- fast on one local machine
- brittle across builders
- impossible to trust publicly

## Benchmark Program

### Fixture Types

1. Small fixture
   - tens of libraries
   - `json_serializable`

2. Medium fixture
   - hundreds of libraries
   - `freezed + json_serializable`

3. Service-heavy fixture
   - `injectable`
   - broad imports

4. Optional heavy fixture
   - `drift` or comparable AST-heavy builder

### Metrics

- initial build
- no-op rebuild
- one-file incremental rebuild
- median and p95 repeated rebuild latency
- daemon startup
- memory use

### Output Correctness

Compare:

- generated file presence
- generated file contents
- exit behavior under failures

## Compatibility Matrix

Track:

- supported `build_runner` version ranges
- Dart SDK versions
- OS support
- builder stack support

## Tasks

### 1. Build Fixture Generator or Fixture Set

Decide whether to:

- check in fixtures
- generate fixtures
- or mix both

Recommended:

- small checked-in fixtures
- medium generated fixtures

### 2. Create Benchmark Runner

The runner should execute:

- standard `build_runner`
- `fast_build_runner`
- same fixture
- same scenario

### 3. Create Regression Thresholds

Examples:

- fail if no-op latency regresses by more than 15%
- fail if incremental latency regresses by more than 10%
- fail if outputs differ unexpectedly

### 4. Add Compatibility Test Matrix

At minimum:

- Linux
- macOS
- supported `build_runner` range

## Acceptance Criteria

- benchmark runner exists
- output diffing exists
- compatibility report exists
- at least one public-ready performance table exists

## Complexity / Risk

- Complexity: `6/10`
- Strategic importance: `10/10`
- Confidence: `9/10`
