# Local State Lifecycle MVP

The first dependency lifecycle is executable end to end:

```bash
asmory init
asmory add simd-dot
asmory status
```

Immediately after add the state is `Exact`.

After a human or AI edits `.asmory/deps/simd-dot/`, `asmory status` recomputes
the tree and reports `Modified`. No metadata flag is flipped.

To deliberately discard the local derivative:

```bash
asmory restore simd-dot
```

Restore uses the Artifact locked in `asm.lock`, verifies/materializes it through
the existing cache pipeline, checks the canonical tree fingerprint, and replaces
the local tree without changing `asm.toml` or `asm.lock`.

A missing tree is reported as `Missing` and can also be restored.

Status is fully offline. Restore also works offline when the exact locked
Artifact is already present in the verified global cache.

This implements the core rule:

> **Local-visible by default, Git-tracked when diverged.**

The next lifecycle milestone can build on Modified state with explicit vendor,
patch, and fork transitions.
