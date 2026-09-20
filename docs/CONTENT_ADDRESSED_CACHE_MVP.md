# Content-addressed Cache MVP

The third local-workflow milestone adds:

```bash
asmory cache simd-dot
```

The exact source Artifact SHA comes from resolver metadata.

```text
Resolver Artifact identity
        ↓
lookup SHA-256 object
        ↓
rehash existing bytes
   exact hit ───────────→ reuse
        │
       miss
        ↓
verified acquisition
        ↓
atomic no-clobber publish
        ↓
read-only content object
```

A verified hit works with the Registry offline.

An object stored at the expected digest path with wrong bytes is a corruption
error, not a cache hit.

This milestone still performs no archive extraction and creates no project
dependency state.
