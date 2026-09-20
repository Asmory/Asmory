#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$PWD}"
cd "$ROOT"

BIN="$ROOT/build/asmory"
STATE="$ROOT/build/asmory-state"
REGISTRY="$ROOT/build/asmory-registry"
BASE="http://127.0.0.1:18080"
LOG="$ROOT/build/asmory-state-smoke-registry.log"

for x in "$BIN" "$STATE" "$REGISTRY"; do
  [[ -x "$x" ]] || {
    echo "state-smoke: missing executable: $x" >&2
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
    echo "state-smoke: port 18080 remains occupied" >&2
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

project="$tmp/project"
mkdir "$project"
cd "$project"

"$BIN" init >/dev/null
grep -q '^\.restore/$' .asmory/.gitignore
echo "== restore runtime directory is ignored =="
"$BIN" add simd-dot >/dev/null

manifest_sha="$(sha256sum asm.toml | awk '{print $1}')"
lock_sha="$(sha256sum asm.lock | awk '{print $1}')"

echo "== exact immediately after add =="
status="$("$BIN" status)"
grep -q '^Workspace dependency status' <<<"$status"
grep -q 'state       Exact' <<<"$status"
grep -Eq 'base tree   [0-9a-f]{64}$' <<<"$status"
grep -Eq 'local tree  [0-9a-f]{64}$' <<<"$status"

base_tree="$(grep '^materialized_tree_sha256 = ' asm.lock | cut -d'"' -f2)"
local_tree="$("$STATE" tree-hash .asmory/deps/simd-dot)"
[[ "$base_tree" == "$local_tree" ]]

echo "== status is local-only =="
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=""
export ASMORY_REGISTRY_URL="http://127.0.0.1:1"

offline="$("$BIN" status)"
grep -q 'state       Exact' <<<"$offline"

echo "== byte edit -> Modified -> restore -> Exact =="
printf '\n# modified locally\n' >> .asmory/deps/simd-dot/src/dot.S
"$BIN" status | grep -q 'state       Modified'
"$BIN" restore simd-dot | grep -q '^Dependency restored'
"$BIN" status | grep -q 'state       Exact'
! grep -q 'modified locally' .asmory/deps/simd-dot/src/dot.S

echo "== extra file -> Modified =="
printf 'experiment\n' > .asmory/deps/simd-dot/local-experiment.txt
"$BIN" status | grep -q 'state       Modified'
"$BIN" restore simd-dot >/dev/null
[[ ! -e .asmory/deps/simd-dot/local-experiment.txt ]]
"$BIN" status | grep -q 'state       Exact'

echo "== executable-bit change -> Modified =="
chmod +x .asmory/deps/simd-dot/src/dot.S
"$BIN" status | grep -q 'state       Modified'
"$BIN" restore simd-dot >/dev/null
"$BIN" status | grep -q 'state       Exact'

echo "== missing file -> Modified =="
rm .asmory/deps/simd-dot/src/dot.S
"$BIN" status | grep -q 'state       Modified'
"$BIN" restore simd-dot >/dev/null
[[ -f .asmory/deps/simd-dot/src/dot.S ]]
"$BIN" status | grep -q 'state       Exact'

echo "== missing tree -> Missing -> restore from offline cache =="
rm -rf .asmory/deps/simd-dot
"$BIN" status | grep -q 'state       Missing'
"$BIN" restore simd-dot >/dev/null
"$BIN" status | grep -q 'state       Exact'

echo "== status/restore never rewrite manifest or lock =="
[[ "$manifest_sha" == "$(sha256sum asm.toml | awk '{print $1}')" ]]
[[ "$lock_sha" == "$(sha256sum asm.lock | awk '{print $1}')" ]]

echo "== corrupt cache makes restore fail without erasing local edits =="
printf '\n# preserve me on failed restore\n' >> .asmory/deps/simd-dot/src/dot.S
"$BIN" status | grep -q 'state       Modified'

artifact="$(grep '^artifact_sha256 = ' asm.lock | cut -d'"' -f2)"
object="$ASMORY_CACHE_HOME/objects/sha256/$artifact"
chmod 0644 "$object"
printf 'corrupt\n' > "$object"

local_before="$(sha256sum .asmory/deps/simd-dot/src/dot.S | awk '{print $1}')"

set +e
"$BIN" restore simd-dot >"$tmp/corrupt-restore.out" 2>&1
rc=$?
set -e

[[ "$rc" -eq 17 ]]
[[ "$local_before" == "$(sha256sum .asmory/deps/simd-dot/src/dot.S | awk '{print $1}')" ]]
grep -q 'cannot obtain locked Artifact from cache' "$tmp/corrupt-restore.out"

echo "state-smoke: ok"
