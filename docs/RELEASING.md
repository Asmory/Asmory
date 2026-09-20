# Releasing Asmory

Asmory uses annotated `vMAJOR.MINOR.PATCH` Git tags.

The release workflow builds and validates the project on Linux x86-64, creates
release archives, computes SHA-256 checksums, and publishes the assets to the
GitHub Release associated with the tag.

## Local release

```bash
./scripts/release.sh v0.1.0
```

The helper refuses to release from a dirty worktree and runs the full build,
registry smoke test, and CLI smoke test before creating the tag.
