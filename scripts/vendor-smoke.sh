#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$PWD}"
cd "$ROOT"

BIN="$ROOT/build/asmory"
STATE="$ROOT/build/asmory-state"
REGISTRY="$ROOT/build/asmory-registry"
BASE="http://127.0.0.1:18080"
LOG="$ROOT/build/asmory-vendor-smoke-registry.log"

for x in "$BIN" "$STATE" "$ROOT/build/asmory-vendor" "$REGISTRY"; do
  [[ -x "$x" ]] || {
    echo "vendor-smoke: missing executable: $x" >&2
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
    echo "vendor-smoke: port 18080 remains occupied" >&2
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

echo "== Exact registry dependency -> project-owned vendor =="
project="$tmp/exact"
mkdir "$project"
cd "$project"
git init -q
git config user.email smoke@example.invalid
git config user.name "Asmory Smoke"

"$BIN" init >/dev/null
"$BIN" add simd-dot >/dev/null

status="$("$BIN" status)"
grep -q 'source      registry' <<<"$status"
grep -q 'ownership   registry-derived' <<<"$status"
grep -q 'state       Exact' <<<"$status"

base_tree="$("$STATE" tree-hash .asmory/deps/simd-dot)"
"$BIN" vendor simd-dot | grep -q '^Dependency vendored$'

[[ ! -e .asmory/deps/simd-dot ]]
[[ -f vendor/simd-dot/src/dot.S ]]
[[ "$base_tree" == "$("$STATE" tree-hash vendor/simd-dot)" ]]

grep -q '^simd-dot = { path = "vendor/simd-dot" }$' asm.toml
grep -q '^source_kind = "vendor"$' asm.lock
grep -q '^vendor_path = "vendor/simd-dot"$' asm.lock
grep -q "^vendor_origin_tree_sha256 = \"$base_tree\"$" asm.lock

status="$("$BIN" status)"
grep -q 'source      vendor' <<<"$status"
grep -q 'ownership   project' <<<"$status"
grep -q 'state       Exact' <<<"$status"
grep -q 'divergence  project-owned' <<<"$status"
grep -q 'path        vendor/simd-dot' <<<"$status"

echo "== vendor tree is Git-visible =="
if git check-ignore -q vendor/simd-dot/src/dot.S; then
  echo "vendor-smoke: vendored source is unexpectedly ignored" >&2
  exit 1
fi
git status --short --untracked-files=all | grep -q 'vendor/simd-dot/src/dot.S'

echo "== registry-only lifecycle commands refuse project-owned source =="
vendor_tree_before="$("$STATE" tree-hash vendor/simd-dot)"

for cmd in restore patch reapply; do
  set +e
  "$BIN" "$cmd" simd-dot >"$tmp/$cmd-vendor.out" 2>&1
  rc=$?
  set -e
  [[ "$rc" -ne 0 ]]
  grep -Eq 'vendored|project-owned|registry' "$tmp/$cmd-vendor.out"
  [[ "$vendor_tree_before" == "$("$STATE" tree-hash vendor/simd-dot)" ]]
done

echo "== project edits stay project-owned =="
printf '\n# owned by this project\n' >> vendor/simd-dot/src/dot.S
status="$("$BIN" status)"
grep -q 'source      vendor' <<<"$status"
grep -q 'ownership   project' <<<"$status"
grep -q 'state       Modified' <<<"$status"
grep -q 'divergence  project-owned' <<<"$status"

echo "== Modified captured-patch tree can transition to full vendor ownership =="
project2="$tmp/modified"
mkdir "$project2"
cd "$project2"
git init -q
git config user.email smoke@example.invalid
git config user.name "Asmory Smoke"

"$BIN" init >/dev/null
"$BIN" add simd-dot >/dev/null
printf '\n# local tuned variant\n' >> .asmory/deps/simd-dot/src/dot.S
printf 'project note\n' > .asmory/deps/simd-dot/local-note.txt
"$BIN" patch simd-dot >/dev/null

active="$(cat .asmory/patches/simd-dot/active)"
target_before="$("$STATE" tree-hash .asmory/deps/simd-dot)"

"$BIN" vendor simd-dot >/dev/null
[[ "$target_before" == "$("$STATE" tree-hash vendor/simd-dot)" ]]
[[ -f ".asmory/patches/simd-dot/deltas/$active.json" ]]

status="$("$BIN" status)"
grep -q 'source      vendor' <<<"$status"
grep -q 'state       Modified' <<<"$status"
grep -q 'divergence  project-owned' <<<"$status"
grep -q "saved patch $active" <<<"$status"

echo "== transition is local-only and still works with Registry offline =="
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=""
export ASMORY_REGISTRY_URL="http://127.0.0.1:1"

project3="$tmp/offline"
mkdir "$project3"
cd "$project3"
"$BIN" init >/dev/null
"$BIN" add simd-dot >/dev/null
printf '\n# offline ownership transition\n' >> .asmory/deps/simd-dot/src/dot.S
"$BIN" vendor simd-dot >/dev/null
[[ -f vendor/simd-dot/src/dot.S ]]
"$BIN" status | grep -q 'ownership   project'

echo "== existing vendor destination is fail-closed and preserves registry tree =="
project4="$tmp/conflict"
mkdir "$project4"
cd "$project4"
"$BIN" init >/dev/null
"$BIN" add simd-dot >/dev/null
mkdir -p vendor/simd-dot
printf 'preexisting\n' > vendor/simd-dot/keep.txt

before="$("$STATE" tree-hash .asmory/deps/simd-dot)"
set +e
"$BIN" vendor simd-dot >"$tmp/vendor-conflict.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 20 ]]
grep -q 'vendor destination already exists' "$tmp/vendor-conflict.out"
[[ "$before" == "$("$STATE" tree-hash .asmory/deps/simd-dot)" ]]
grep -q '^simd-dot = "\*"$' asm.toml
[[ "$(cat vendor/simd-dot/keep.txt)" == "preexisting" ]]

echo "vendor-smoke: ok"
