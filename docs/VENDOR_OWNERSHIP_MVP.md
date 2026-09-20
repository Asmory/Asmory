# Vendor Ownership MVP

Asmory now has two reproducible ways to handle a local derivative.

Compact derivative:

```text
Modified
  -> asmory patch
  -> deterministic .asmory/patches/ record
```

Full project ownership:

```text
Exact or Modified
  -> asmory vendor
  -> vendor/<package>
  -> path dependency in asm.toml
```

Vendoring does not publish anything and performs no Registry resolution.

It transfers the current visible local source tree into project-owned,
Git-visible source while preserving its Registry ancestry in `asm.lock`.

The transition is transactional and verifies the tree before and after
publication.

After vendoring, Registry-oriented `restore`, `patch`, and `reapply` stop
applying to that dependency. This prevents a package-manager command from
silently overwriting project-owned code.

The remaining ownership transition is fork/publication: turning project-owned
or patched work into a new independently identified Asmory Implementation /
Machine Variant.
