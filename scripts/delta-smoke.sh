#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$PWD}"
cd "$ROOT"

BIN="$ROOT/build/asmory"
DELTA="$ROOT/build/asmory-delta"
STATE="$ROOT/build/asmory-state"
REGISTRY="$ROOT/build/asmory-registry"
BASE="http://127.0.0.1:18080"
LOG="$ROOT/build/asmory-delta-smoke-registry.log"

for x in "$BIN" "$DELTA" "$STATE" "$REGISTRY"; do
  [[ -x "$x" ]] || {
    echo "delta-smoke: missing executable: $x" >&2
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
    echo "delta-smoke: port 18080 remains occupied" >&2
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

git init -q
git config user.email smoke@example.invalid
git config user.name "Asmory Smoke"

"$BIN" init >/dev/null
"$BIN" add simd-dot >/dev/null

echo "== Exact cannot be captured =="
set +e
"$BIN" patch simd-dot >"$tmp/exact-patch.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 19 ]]
grep -q 'there is no local divergence to capture' "$tmp/exact-patch.out"

echo "== create a multi-operation local derivative =="
printf '\n# tuned by local agent\n' >> .asmory/deps/simd-dot/src/dot.S
printf 'local note\n' > .asmory/deps/simd-dot/local-note.txt
chmod +x .asmory/deps/simd-dot/src/dot.S
rm .asmory/deps/simd-dot/README.md

status="$("$BIN" status)"
grep -q 'state       Modified' <<<"$status"
grep -q 'divergence  uncaptured' <<<"$status"

target_before="$("$STATE" tree-hash .asmory/deps/simd-dot)"

echo "== capture deterministic patch =="
capture="$("$BIN" patch simd-dot)"
grep -q '^Local divergence captured$' <<<"$capture"

active="$(cat .asmory/patches/simd-dot/active)"
[[ "$active" =~ ^[0-9a-f]{64}$ ]]
manifest=".asmory/patches/simd-dot/deltas/$active.json"
[[ -f "$manifest" ]]

python3 - "$manifest" "$active" "$target_before" <<'PY'
import hashlib, json, pathlib, sys

path = pathlib.Path(sys.argv[1])
expected_delta = sys.argv[2]
expected_target = sys.argv[3]
raw = path.read_bytes()
assert hashlib.sha256(raw).hexdigest() == expected_delta
obj = json.loads(raw)
assert obj["format"] == "asmory-delta-v1"
assert obj["target_tree_sha256"] == expected_target
assert obj["remove"]
assert obj["put"]
PY

status="$("$BIN" status)"
grep -q 'state       Modified' <<<"$status"
grep -q 'divergence  captured-patch' <<<"$status"
grep -q "saved patch $active" <<<"$status"

echo "== patches are Git-visible while dependency materialization stays ignored =="
git check-ignore -q .asmory/deps/simd-dot/src/dot.S
if git check-ignore -q .asmory/patches/simd-dot/active; then
  echo "delta-smoke: captured patch is unexpectedly ignored" >&2
  exit 1
fi
git status --short --untracked-files=all | grep -q '.asmory/patches/simd-dot/active'

echo "== restore keeps patch but returns base Exact =="
"$BIN" restore simd-dot >/dev/null
status="$("$BIN" status)"
grep -q 'state       Exact' <<<"$status"
grep -q 'divergence  none' <<<"$status"
grep -q "saved patch $active" <<<"$status"
[[ -f "$manifest" ]]

echo "== reapply works fully offline =="
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=""
export ASMORY_REGISTRY_URL="http://127.0.0.1:1"

"$BIN" reapply simd-dot | grep -q '^Captured patch reapplied$'
status="$("$BIN" status)"
grep -q 'state       Modified' <<<"$status"
grep -q 'divergence  captured-patch' <<<"$status"
[[ "$("$STATE" tree-hash .asmory/deps/simd-dot)" == "$target_before" ]]
grep -q 'tuned by local agent' .asmory/deps/simd-dot/src/dot.S
[[ -f .asmory/deps/simd-dot/local-note.txt ]]
[[ ! -e .asmory/deps/simd-dot/README.md ]]
[[ -x .asmory/deps/simd-dot/src/dot.S ]]

echo "== new edits after capture become uncaptured =="
printf '\n# second experiment\n' >> .asmory/deps/simd-dot/src/dot.S
status="$("$BIN" status)"
grep -q 'state       Modified' <<<"$status"
grep -q 'divergence  uncaptured' <<<"$status"
grep -q "saved patch $active" <<<"$status"

echo "== reapply refuses to erase uncaptured work =="
local_before="$(sha256sum .asmory/deps/simd-dot/src/dot.S | awk '{print $1}')"
set +e
"$BIN" reapply simd-dot >"$tmp/refuse.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 19 ]]
grep -q 'refusing to overwrite uncaptured Modified work' "$tmp/refuse.out"
[[ "$local_before" == "$(sha256sum .asmory/deps/simd-dot/src/dot.S | awk '{print $1}')" ]]

echo "== corrupted captured blob fails without damaging Exact base =="
"$BIN" restore simd-dot >/dev/null

blob="$(find .asmory/patches/simd-dot/blobs -type f | head -n1)"
chmod 0644 "$blob"
printf 'corrupt blob\n' > "$blob"

base_before="$("$STATE" tree-hash .asmory/deps/simd-dot)"

set +e
"$BIN" reapply simd-dot >"$tmp/corrupt-delta.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 19 ]]
[[ "$base_before" == "$("$STATE" tree-hash .asmory/deps/simd-dot)" ]]
grep -Eq 'blob verification failed|delta blob' "$tmp/corrupt-delta.out"

echo "delta-smoke: ok"
