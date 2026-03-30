# Iteration 03: Rust Daemon and Protocol

## Goal

Create the Rust daemon that owns hot-path incremental state and can talk to the
Dart adapter predictably.

## Main Outcome

A daemon process that:

- watches filesystem changes
- normalizes them into update batches
- persists relevant state
- exposes them through a narrow protocol

## Why This Iteration Matters

This is where the project starts to become a performance tool rather than just
an alternative command loop.

## Daemon Responsibilities

- watch root package and relevant dependencies
- normalize raw file events
- debounce and batch updates
- persist project state
- expose daemon lifecycle commands

The daemon does not own:

- build script freshness
- builder factory loading
- `build.yaml` parsing
- final invalidation semantics inside `AssetGraph`

Not yet required here:

- complete import graph invalidation
- full smart triggers
- complex scheduling heuristics

## Protocol Design

Recommended alpha protocol:

- line-delimited JSON
- request/response plus async event stream
- one version field on every envelope

Core messages:

- `hello`
- `watch_project`
- `project_snapshot`
- `file_batch`
- `rebuild_request`
- `shutdown`
- `health`

## Tasks

### 1. Build the Daemon Shell

Set up:

- Rust crate
- command entry point
- config loading
- logging
- lifecycle management

### 2. Add File Watching

Implement:

- project root watching
- dependency package watching if needed
- stable path normalization
- event collapsing

Match the realities of upstream package watching:

- package root based watching
- nested package path normalization
- root-relative path mapping suitable for `AssetId`

### 3. Add Batch Aggregation

The daemon must convert noisy watcher events into meaningful batches.

Requirements:

- collapse duplicate modify storms
- normalize create/delete/modify sequences
- add configurable debounce window

The daemon should be able to emit both:

- raw batches
- classified batches with confidence markers for later heuristics

### 4. Add Project State Folder

Use something like:

- `.dart_tool/fast_build_runner/`

State may include:

- daemon pid/socket info
- graph snapshot later
- protocol version
- logs or traces

### 5. Add Minimal Protocol Client in Dart

The Dart side must be able to:

- start daemon if absent
- connect
- request watch mode
- receive file batches

### 6. Add Mock Benchmark Logging

Before optimization, measure:

- daemon startup latency
- event delivery latency
- batch size behavior

## Acceptance Criteria

- daemon can watch a fixture project
- Dart can receive structured file batches
- daemon restarts cleanly
- project state directory is consistent
- event batches can be mapped cleanly to `AssetId -> ChangeType`

## Complexity / Risk

- Complexity: `6/10`
- Performance importance: `8/10`
- Confidence: `8/10`

## Constraints

Do not add graph semantics yet unless absolutely needed.
This iteration is about solid daemon infrastructure first.
