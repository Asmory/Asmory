# Performance Contract and Evidence — Draft 0.1

Asmory is not only a place to publish Assembly.

It is a place to make Assembly faster **without turning benchmark anecdotes
into resolver truth**.

## Contract

A Performance Contract defines how a measurement is made:

```toml
benchmark_id = "simd-dot/dot-f32-v1"
primary_metric = "ns_per_element"
direction = "lower"
minimum_samples = 11
regression_threshold_percent = 5.0
```

It also defines workload, timer, warmup, iteration count, affinity policy,
machine metadata requirements and raw-sample retention.

The Contract itself is content-addressed. Evidence should record its exact
digest.

## Automatic performance power sessions

The first reference package, `simd-dot`, uses an automatic benchmark power
session.

Before measurement Asmory performs:

```text
detect supported host power controls
        ↓
save current policy
        ↓
switch supported controls to performance
        ↓
verify the transition
        ↓
run benchmark
        ↓
restore the original policy
```

A supported interface that fails to transition is a hard benchmark error.

Asmory may use compatibility fallback only when the host exposes no supported
controllable power-policy interface, for example some containers, virtual
machines or fixed-policy systems.

Fallback measurements remain useful local diagnostics, but are not eligible for
accepted Registry Performance Evidence under this Contract.

```text
unsupported host
    → compatibility fallback

supported host + transition/permission failure
    → reject
```

## Evidence binds to an exact Artifact

Every record must identify:

```text
Project
Release
Variant
Artifact SHA-256
Performance Contract ID + digest
machine profile
measurement protocol
raw samples
```

Performance numbers from an older Artifact are historical information.

They are not evidence for a newer Artifact merely because the package name and
version text look similar during development.

## Local candidate vs accepted Registry evidence

Running a benchmark creates a **local candidate Evidence record**.

```text
local benchmark
    ↓
candidate Evidence
    ↓
schema / Artifact / Contract validation
    ↓
optional submission
    ↓
Registry accepted Evidence
```

A candidate is useful to humans and AI immediately.

It does not automatically change the global resolver.

## Append-only Evidence

Performance Evidence is independent from immutable Release content.

A Release does not need to be rewritten when another machine contributes a new
valid measurement.

Conceptually:

```text
immutable Release / Artifact
        ↑
        ├── Evidence from machine A
        ├── Evidence from machine B
        └── Evidence from machine C
```

Each Evidence record references the immutable Artifact digest.

## Comparability

Two records are directly comparable only when their relevant cohort matches:

```text
Performance Contract + version/digest
workload
measurement protocol
thread/affinity policy
hardware profile class
```

Different hardware remains valuable evidence, but raw values must not be placed
on a naive universal leaderboard.

## A/B order bias

Variant comparisons should not always measure A before B.

Asmory's example benchmark alternates:

```text
AB
BA
AB
BA
...
```

and retains the order in every raw sample.

This does not eliminate all benchmark noise, but it makes a common ordering bias
visible and easier to diagnose.

## Resolver rule

The resolver order is:

```text
semantic compatibility
        ↓
Machine Contract
        ↓
trust policy
        ↓
comparable accepted Performance Evidence
        ↓
selection
```

Performance can rank survivors.

Performance can never make an incompatible or untrusted candidate legal.

When no accepted comparable current-Artifact Evidence exists, Asmory should say
so explicitly and use a declared fallback policy such as stable-Variant
preference.

## No forced winning

Asmory does not require a package to beat its baseline.

Asmory requires performance claims to be measurable, reproducible and properly
scoped.

A machine-local observation should be labeled as such:

```text
faster on this machine
```

not:

```text
globally faster
```

## Optimization loop

The intended AI/human loop is:

```text
modify Variant
    ↓
Conformance
    ↓
benchmark
    ↓
validate Evidence
    ↓
inspect machine-local result
    ↓
collect broader comparable Evidence
    ↓
publish new Variant / ranking policy when justified
```

Evidence drives optimization; it does not redefine correctness.
