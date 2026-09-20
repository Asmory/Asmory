# Publication Promotion Gate MVP

This milestone closes the first complete publication state machine:

```text
Package source
  -> publish-prepare
  -> deterministic local candidate
  -> publish
  -> authenticated persistent staging
  -> promote
  -> active immutable Release
  -> public resolver-facing read API
```

Promotion is intentionally server-derived.

The Registry re-opens the exact staged source Artifact, validates its package,
semantic, target, build, export and conformance metadata, recomputes the
Semantic Facet fingerprint and derives one active Machine Variant from the
authoritative `asm.toml` target contract.

It does not execute package code. The active record explicitly says
`code_execution = false`, and review remains `unreviewed`.

This is enough to make publication identity and resolver-facing persistence
real without confusing metadata validation with security review or semantic
proof.
