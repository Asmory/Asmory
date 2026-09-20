# Resolver MVP

This milestone turns the first part of Asmory's resolver philosophy into
executable behavior.

## Implemented

```text
rendered Registry Release JSON
        ↓
generated Assembly metadata include
        ↓
Assembly CLI
        ↓
CPUID/XGETBV Machine Contract check
        ↓
resolve / explain / audit
```

The Registry Release JSON is the source of truth for Project/Release, Provider,
Capability, Profile, dependency model, Artifact policy, Machine Variants, source
Artifact SHA-256, review state, registry safety state and Advisories.

The CLI no longer needs a second manually maintained copy of the Artifact
digest.

## Commands

```bash
asmory resolve simd-dot
asmory explain simd-dot
asmory audit simd-dot
```

`resolve` checks the real host AVX/OSXSAVE state through the existing
CPUID/XGETBV path, then verifies AVX2 + FMA before selecting the stable generic
Variant.

`explain` exposes user intent, expanded defaults, semantic identity, Machine
Contract, candidates and final selection.

`audit` keeps integrity and security separate. It reports the exact published
source Artifact digest, but local integrity remains `not evaluated` until
materialization exists. Review and Advisory state are shown without claiming
that an exact Artifact is safe.

## Deliberate limitations

This milestone still uses the embedded bootstrap Registry index.

Not yet implemented:

```text
remote HTTP Registry client in the CLI
asm.lock
global content-addressed cache
project-local materialization
Exact/Modified tree hashing
advisory feed refresh
signature/provenance verification
performance-evidence ranking
```

Those become the next milestones.

## Invariants already enforced

```text
Registry metadata drives CLI Artifact identity.
Host compatibility is checked before selection.
Source-preferred and leaf-first defaults are explicit.
Exact Artifact identity is not presented as a safety verdict.
Experimental Variant status does not silently outrank the stable Variant.
```
