# Repository Workspace MVP

Asmory now models a development repository independently from Package identity.

A repository may declare multiple Package roots in `asmory.workspace.toml`.
Each member has an `asmory.package.toml`.

The bootstrap command:

```bash
asmory workspace
```

validates and lists repository Packages.

The maintained helper also supports:

```bash
asmory-workspace check
asmory-workspace path simd-dot
asmory-workspace metadata simd-dot
asmory-workspace provenance simd-dot
asmory-workspace publish-check simd-dot
asmory-workspace pack simd-dot output.tar.gz
```

`pack` first enforces the self-contained Package boundary and then creates a
deterministic archive from the Package source closure. Repository-control
metadata such as `asmory.package.toml` is excluded from source Artifact v1.

The publish/development model can derive Git provenance:

```text
repository + commit + Package subdir + dirty state
```

This metadata is descriptive provenance only. Resolver identity and Artifact
verification remain Package / Release / Variant / Artifact concerns.
