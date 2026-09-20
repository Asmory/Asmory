#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$PWD}"
cd "$ROOT"

BIN="$ROOT/build/asmory"
ACQUIRE="$ROOT/build/asmory-acquire"
CACHE="$ROOT/build/asmory-cache"
ADD="$ROOT/build/asmory-add"
MATERIALIZE="$ROOT/build/asmory-materialize"
REGISTRY="$ROOT/build/asmory-registry"
BASE="http://127.0.0.1:18080"
LOG="$ROOT/build/asmory-add-smoke-registry.log"

for x in "$BIN" "$ACQUIRE" "$CACHE" "$ADD" "$MATERIALIZE" "$REGISTRY"; do
  [[ -x "$x" ]] || {
    echo "add-smoke: missing executable: $x" >&2
    exit 2
  }
done

mapfile -t stale < <(pgrep -x asmory-registry || true)
if ((${#stale[@]})); then
  kill "${stale[@]}" 2>/dev/null || true
  for _ in $(seq 1 40); do
    alive=0
    for pid in "${stale[@]}"; do
      kill -0 "$pid" 2>/dev/null && alive=1 || true
    done
    (( alive == 0 )) && break
    sleep 0.05
  done
fi

if command -v ss >/dev/null 2>&1; then
  if ss -ltn "sport = :18080" | awk 'NR>1{found=1} END{exit !found}'; then
    echo "add-smoke: port 18080 remains occupied" >&2
    exit 1
  fi
fi

"$REGISTRY" >"$LOG" 2>&1 &
PID=$!
tmp="$(mktemp -d)"

cleanup() {
  if [[ -n "${PID:-}" ]]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

ready=0
for _ in $(seq 1 60); do
  if ! kill -0 "$PID" 2>/dev/null; then
    cat "$LOG" >&2 || true
    exit 1
  fi
  if curl -fsS "$BASE/" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.05
done
[[ "$ready" == 1 ]]

export PATH="$ROOT/build:$PATH"
export ASMORY_REGISTRY_URL="$BASE"
export ASMORY_CACHE_HOME="$tmp/cache"

expected="$(sha256sum "$ROOT/build/packages/simd-dot-0.1.0.tar.gz" | awk '{print $1}')"
object="$ASMORY_CACHE_HOME/objects/sha256/$expected"

echo "== add requires workspace =="
mkdir "$tmp/no-workspace"
cd "$tmp/no-workspace"
set +e
"$BIN" add simd-dot >"$tmp/no-workspace.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 9 ]]
grep -q "run.*asmory init" "$tmp/no-workspace.out"

echo "== first end-to-end add =="
mkdir "$tmp/project"
cd "$tmp/project"
"$BIN" init >/dev/null
"$BIN" add simd-dot | tee "$tmp/add.out"
grep -q '^Dependency added$' "$tmp/add.out"

grep -q '^simd-dot = "\*"$' asm.toml
grep -q '^dependency_count = 1$' asm.lock
grep -q '^name = "simd-dot"$' asm.lock
grep -q '^release = "0.1.0"$' asm.lock
grep -Eq '^semantic_fingerprint = "[0-9a-f]{64}"$' asm.lock
grep -q '^profile = "asmory/simd-dot-core@1.0.0"$' asm.lock
grep -q '^provider = "Asmory/Asmory"$' asm.lock
grep -q '^variant = "x86_64-avx2-generic"$' asm.lock
grep -q "^artifact_sha256 = \"$expected\"$" asm.lock
grep -q '^tree_hash_schema = "asmory-tree-v1"$' asm.lock
grep -Eq '^materialized_tree_sha256 = "[0-9a-f]{64}"$' asm.lock
grep -q '^review_state = "unreviewed"$' asm.lock
grep -q '^registry_safety = "normal"$' asm.lock

[[ -f .asmory/deps/simd-dot/src/dot.S ]]
[[ -f .asmory/deps/simd-dot/semantics.toml ]]
[[ -f "$object" ]]
[[ "$(sha256sum "$object" | awk '{print $1}')" == "$expected" ]]

locked_tree="$(grep '^materialized_tree_sha256 = ' asm.lock | cut -d'"' -f2)"
actual_tree="$("$ROOT/build/asmory-state" tree-hash .asmory/deps/simd-dot)"
[[ "$locked_tree" == "$actual_tree" ]]

if find .asmory/deps/simd-dot -type l | grep -q .; then
  echo "materialized dependency unexpectedly contains symlinks" >&2
  exit 1
fi

echo "== local copy is writable and detached from immutable cache =="
cache_before="$(sha256sum "$object" | awk '{print $1}')"
printf '\n# local experiment\n' >> .asmory/deps/simd-dot/src/dot.S
grep -q 'local experiment' .asmory/deps/simd-dot/src/dot.S
[[ "$(sha256sum "$object" | awk '{print $1}')" == "$cache_before" ]]

echo "== duplicate add refuses to erase local work =="
manifest_before="$(sha256sum asm.toml | awk '{print $1}')"
lock_before="$(sha256sum asm.lock | awk '{print $1}')"
local_before="$(sha256sum .asmory/deps/simd-dot/src/dot.S | awk '{print $1}')"

set +e
"$BIN" add simd-dot >"$tmp/duplicate.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 15 ]]
[[ "$(sha256sum asm.toml | awk '{print $1}')" == "$manifest_before" ]]
[[ "$(sha256sum asm.lock | awk '{print $1}')" == "$lock_before" ]]
[[ "$(sha256sum .asmory/deps/simd-dot/src/dot.S | awk '{print $1}')" == "$local_before" ]]

echo "== offline add from verified cache =="
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=""
export ASMORY_REGISTRY_URL="http://127.0.0.1:1"

mkdir "$tmp/offline-project"
cd "$tmp/offline-project"
"$BIN" init >/dev/null
"$BIN" add simd-dot >"$tmp/offline.out"
grep -q '^Dependency added$' "$tmp/offline.out"
[[ -f .asmory/deps/simd-dot/src/dot.S ]]

echo "== malicious archive rejection =="
mkdir "$tmp/malicious"
cd "$tmp/malicious"

python3 - "$tmp/malicious" <<'PY'
import io
from pathlib import Path
import tarfile
import sys

root = Path(sys.argv[1])
absolute_target = root / "absolute-escape"

cases = {
    "traversal.tar.gz": ("file", "simd-dot/../../escape"),
    "absolute.tar.gz": ("file", str(absolute_target)),
    "symlink.tar.gz": ("symlink", "simd-dot/link"),
    "hardlink.tar.gz": ("hardlink", "simd-dot/hard"),
    "fifo.tar.gz": ("fifo", "simd-dot/fifo"),
}

for filename, (kind, name) in cases.items():
    path = root / filename
    with tarfile.open(path, "w:gz") as tf:
        d = tarfile.TarInfo("simd-dot")
        d.type = tarfile.DIRTYPE
        d.mode = 0o755
        tf.addfile(d)

        info = tarfile.TarInfo(name)

        if kind == "file":
            payload = b"escape"
            info.size = len(payload)
            info.mode = 0o644
            tf.addfile(info, io.BytesIO(payload))
        elif kind == "symlink":
            info.type = tarfile.SYMTYPE
            info.linkname = "../../outside"
            tf.addfile(info)
        elif kind == "hardlink":
            info.type = tarfile.LNKTYPE
            info.linkname = "/etc/passwd"
            tf.addfile(info)
        elif kind == "fifo":
            info.type = tarfile.FIFOTYPE
            tf.addfile(info)
PY

for archive in traversal.tar.gz absolute.tar.gz symlink.tar.gz hardlink.tar.gz fifo.tar.gz; do
  sha="$(sha256sum "$archive" | awk '{print $1}')"
  mkdir "$tmp/materialize-$archive"

  set +e
  "$MATERIALIZE" simd-dot "$sha" "$PWD/$archive" "$tmp/materialize-$archive" \
    >"$tmp/$archive.out" 2>&1
  rc=$?
  set -e

  [[ "$rc" -eq 16 ]]
  [[ ! -e "$tmp/materialize-$archive/simd-dot" ]]
done

[[ ! -e "$tmp/escape" ]]
[[ ! -e "$tmp/malicious/absolute-escape" ]]

echo "== materialization failure leaves manifest and lock unchanged =="
mkdir "$tmp/rollback"
cd "$tmp/rollback"
"$BIN" init >/dev/null
manifest_before="$(sha256sum asm.toml | awk '{print $1}')"
lock_before="$(sha256sum asm.lock | awk '{print $1}')"
chmod 0555 .asmory/deps

set +e
"$BIN" add simd-dot >"$tmp/rollback.out" 2>&1
rc=$?
set -e

chmod 0755 .asmory/deps
[[ "$rc" -ne 0 ]]
[[ "$(sha256sum asm.toml | awk '{print $1}')" == "$manifest_before" ]]
[[ "$(sha256sum asm.lock | awk '{print $1}')" == "$lock_before" ]]
[[ ! -e .asmory/deps/simd-dot ]]

echo "add-smoke: ok"
