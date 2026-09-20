# Evidence Loop MVP

This milestone implements the performance side of Asmory's design.

## Registry

A Release now exposes a Performance Evidence endpoint:

```text
GET /api/v1/packages/simd-dot/0.1.0/evidence
```

For the current Artifact the Registry intentionally starts with:

```text
accepted_records = []
status = no-accepted-current-artifact-evidence
```

That is not a missing feature disguised as success.

It is an explicit statement that the Registry has no accepted comparable
performance evidence for this exact Artifact yet.

## CLI

```bash
asmory evidence simd-dot
```

shows:

```text
benchmark contract
contract digest
current evidence state
accepted record count
resolver ranking policy
```

`asmory explain` also states when selection falls back to Variant stability
because comparable accepted Evidence is absent.

## Automatic performance power session

`simd-dot` is the first reference package to adopt managed benchmark power
policy.

`make optimize-simd-dot` now:

```text
save current host policy
→ switch supported controls to performance
→ verify
→ measure
→ restore the original policy
```

Only a host that exposes no supported controllable power-policy interface may
use compatibility fallback. If an interface exists but switching fails, the
benchmark fails instead of silently downgrading.

Use:

```bash
make perf-power-status
```

to inspect the host before measurement.

## Local optimization loop

```bash
make optimize-simd-dot
```

runs:

```text
Conformance Suite
        ↓
A/B benchmark with alternating order
        ↓
candidate Performance Evidence
        ↓
Artifact + Contract validation
        ↓
machine-readable optimization report
```

The generated files stay under `build/` and are not committed automatically.

## Why local evidence does not immediately change the resolver

One fast measurement on one CPU is valuable engineering information.

It is not enough to redefine the package's global default.

The report therefore contains:

```text
global_default_changed = false
```

while preserving the locally faster Variant so an AI or human can continue the
optimization process.

## Three independent evidence families

Asmory deliberately separates:

```text
Conformance Evidence
    observable semantics

Performance Evidence
    speed / cost on defined cohorts

Review / Security Evidence
    trust, anomalies and Advisories
```

A package can be fast and wrong.

A package can be correct and malicious.

A package can be secure and slow.

The Registry must preserve those distinctions.
