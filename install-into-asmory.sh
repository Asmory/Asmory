#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$HOME/asm/Asmory}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$ROOT"
cp -a "$HERE"/. "$ROOT"/

echo "Asmory GitHub bootstrap files installed into:"
echo "  $ROOT"
echo
echo "Next:"
echo "  cd \"$ROOT\" && ./scripts/publish-github.sh"
