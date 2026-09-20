# End-to-end `asmory add` MVP

This milestone turns resolver, acquisition and cache into the first complete
package-manager workflow:

```bash
asmory init
asmory add simd-dot
```

The command performs:

```text
resolve machine legality
  -> exact Registry identity
  -> verified content-addressed cache
  -> safe archive validation
  -> project-local materialization
  -> manifest intent
  -> exact lockfile record
```

The result is visible writable source under `.asmory/deps/simd-dot/`.

The MVP refuses to overwrite an existing dependency, extract unsafe members,
rewrite a non-empty bootstrap workspace, or mutate manifest/lockfile when
materialization fails. Workspace mutations are serialized with a local lock.

Once the exact Artifact is present and verifies in the global cache, another
project can `asmory add simd-dot` while the Registry is offline.

This is the first executable form of:

> **Cache for reuse. Local workspace for understanding and evolution.**

The local-state lifecycle now computes Exact versus Modified from the materialized
tree and implements restore as the first explicit state transition.
