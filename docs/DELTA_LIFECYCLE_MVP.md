# Captured Delta Lifecycle MVP

The local-first workflow now distinguishes experimentation from reproducible
handoff.

```text
asmory add
   ↓
Exact
   ↓ edit
Modified / uncaptured
   ↓ asmory patch
Modified / captured-patch
   ↓ asmory restore
Exact / saved patch available
   ↓ asmory reapply
Modified / captured-patch
```

The captured patch is content-addressed and lives under `.asmory/patches/`,
which is intentionally visible to Git.

The dependency working tree under `.asmory/deps/` remains ignored.

`asmory patch` never changes the current source tree. It reconstructs the locked
base independently, computes a deterministic delta, proves that replay reaches
the same target tree, and only then publishes the patch record.

`asmory reapply` is transactional and refuses to erase unrelated uncaptured
local work.

This provides the first reproducible Modified-dependency handoff without
pretending the local derivative is the original Registry Artifact.
