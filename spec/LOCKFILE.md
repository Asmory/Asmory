# Lockfile — Draft 0.1

`asm.toml` records user intent. `asm.lock` records exact resolver output.

The first dependency record is:

```toml
schema = 1
resolver_policy = "asmory-v1"
dependency_count = 1

[[dependency]]
name = "simd-dot"
intent = "*"
release = "0.1.0"
capability = "math.dot.f32"
semantic_fingerprint = "<sha256>"
profile = "asmory/simd-dot-core@1.0.0"
provider = "Asmory/Asmory"
variant = "x86_64-avx2-generic"
artifact_kind = "source"
artifact_sha256 = "<sha256>"
review_state = "unreviewed"
registry_safety = "normal"
materialized_path = ".asmory/deps/simd-dot"
```

The lockfile intentionally does not contain `exact = true` or
`modified = false`; those values would become stale immediately after an edit.

The lockfile stores the immutable base identity required to recompute local
integrity.

For `asmory add simd-dot`, the manifest records broad intent:

```toml
[dependencies]
simd-dot = "*"
```

while the lockfile records the exact Release, semantics, Provider, Variant and
Artifact chosen by the resolver.

> Convenience is a property of input syntax. Precision is a property of the
> internal model.
