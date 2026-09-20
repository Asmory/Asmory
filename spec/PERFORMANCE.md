# Performance Contract — Draft 0

Asmory is not only a place to publish Assembly.

It is a place to make Assembly faster.

A performance-oriented Variant must provide reproducible evidence rather than
an unsupported claim such as "2x faster".

## Required contract fields

```toml
[performance]
benchmark_id = "dot-f32-v1"
primary_metric = "ns_per_element"
direction = "lower"
baseline = "scalar"
minimum_samples = 11
regression_threshold_percent = 5.0
```

A benchmark contract must also define:

- workload;
- timer;
- warmup;
- iterations;
- thread/CPU-affinity policy;
- required machine metadata;
- raw-sample retention.

## Required evidence

At minimum:

```text
package
release
variant
artifact SHA-256
benchmark_id

CPU model
architecture
kernel / OS
affinity policy

workload
sample count
raw samples

absolute primary metric
baseline metric
code size
```

Optional but strongly encouraged:

```text
cycles
instructions
IPC
branches
branch misses
cache misses
architecture-specific PMU events
```

## Hard rule

Asmory does **not** require a package to beat its baseline.

Asmory requires performance claims to be measurable and reproducible.

That prevents package authors from being forced to cherry-pick favorable
machines or workloads just to publish.

## Comparability

Two Evidence records are directly comparable only when their relevant cohort
matches:

```text
benchmark contract/version
workload
thread/affinity policy
measurement protocol
hardware profile class
```

Different machines are valuable evidence, but they must not be ranked as if
their raw absolute numbers came from the same environment.

## Regression detection

Within a comparable cohort:

```text
previous median
      ↓
new median
      ↓
declared threshold
      ↓
regression / improvement / neutral
```

The first goal is not a global leaderboard.

The first goal is making performance regressions and weak microarchitectures
easy for the community to find.
