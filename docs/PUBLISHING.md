# Publishing Packages

Asmory's role is closer to crates.io / PyPI than to a Git hosting service.

```text
Git forge → develop
asm.toml → package
asmory publish --check
asmory publish
Asmory Registry → resolve/download
```

## Intended CLI

```bash
asmory login
asmory publish --check
asmory publish
asmory yank simd-dot@0.1.0 --reason "incorrect ABI metadata"
asmory owner add simd-dot github:someone
```

The network write path is not implemented yet; these commands define the UX.

## Publish invariants

- normalize the project name before ownership lookup;
- publish a project/version identity once;
- never let an artifact filename later resolve to different bytes;
- record artifact SHA-256 and byte size;
- capture ISA/ABI/target metadata with the Release;
- keep ownership in registry state;
- make yanking non-destructive.

If `0.1.0` is broken, publish `0.1.1` and yank `0.1.0`.
