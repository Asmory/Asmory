#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
ROOT="${ASMORY_ROOT:-$HOME/asm/Asmory}"

if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "usage: $0 vMAJOR.MINOR.PATCH" >&2
  exit 2
fi

cd "$ROOT"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo 'refusing release: worktree is dirty' >&2
  exit 3
fi

make clean
make -j"$(nproc)"
make check
make smoke
make cli-smoke

git fetch --tags origin
if git rev-parse "$VERSION" >/dev/null 2>&1; then
  echo "tag already exists: $VERSION" >&2
  exit 4
fi

git tag -a "$VERSION" -m "Asmory $VERSION"
git push origin main
git push origin "$VERSION"

echo "release tag pushed: $VERSION"
echo "watch: gh run list --workflow=release.yml"
