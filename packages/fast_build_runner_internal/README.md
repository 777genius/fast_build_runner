# fast_build_runner_internal

Internal runtime package for
[`fast_build_runner`](https://github.com/777genius/fast_build_runner).

This package is published only so the public `fast_build_runner` executable can
depend on a hosted package instead of a local path dependency.

It contains unstable implementation details:

- custom bootstrap helpers
- custom child runtime around upstream `BuildPlan` / `BuildSeries`
- hot-path forks used for faster watch / incremental rebuilds
- optional Rust source/watch integration

Do not treat this package as a stable public API.
