# Artifact Acquisition MVP

The second local-workflow milestone adds:

```bash
asmory acquire simd-dot ./simd-dot-0.1.0.tar.gz
```

The command requires an initialized workspace but does not modify its manifest
or lockfile.

```text
Assembly resolver
  -> exact package/release/Artifact SHA
  -> bootstrap transport backend
  -> temporary download
  -> SHA-256 verify
  -> atomic no-clobber output
```

A digest mismatch fails closed.

The command intentionally stops before global cache, archive extraction,
project-local materialization, Exact/Modified tree comparison, and lockfile
dependency records.

> Resolution decides identity. Acquisition only transports bytes for that
> identity.
