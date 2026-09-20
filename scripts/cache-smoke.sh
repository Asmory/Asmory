#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$PWD}"
cd "$ROOT"

BIN="$ROOT/build/asmory"
ACQUIRE="$ROOT/build/asmory-acquire"
CACHE="$ROOT/build/asmory-cache"
REGISTRY="$ROOT/build/asmory-registry"
BASE="http://127.0.0.1:18080"
LOG="$ROOT/build/asmory-cache-smoke-registry.log"

for x in "$BIN" "$ACQUIRE" "$CACHE" "$REGISTRY"; do
  [[ -x "$x" ]] || {
    echo "cache-smoke: missing executable: $x" >&2
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
    echo "cache-smoke: port 18080 remains occupied" >&2
    ss -ltnp "sport = :18080" >&2 || true
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
    echo "cache-smoke: current registry died" >&2
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

echo "== global cache does not require workspace =="
cd "$tmp"
first="$("$BIN" cache simd-dot)"
grep -q '^Cache populated$' <<<"$first"
[[ -f "$object" && ! -L "$object" ]]
[[ "$(sha256sum "$object" | awk '{print $1}')" == "$expected" ]]
[[ "$(stat -c '%a' "$object")" == "444" ]]
[[ ! -e asm.toml ]]
[[ ! -e asm.lock ]]

echo "== cache hit verifies and needs no network =="
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=""

export ASMORY_REGISTRY_URL="http://127.0.0.1:1"
second="$("$BIN" cache simd-dot)"
grep -q '^Cache hit$' <<<"$second"
grep -q 'verification exact' <<<"$second"

echo "== cache identity is digest-only =="
[[ "$(basename "$object")" == "$expected" ]]
[[ "$(dirname "$object")" == "$ASMORY_CACHE_HOME/objects/sha256" ]]

echo "== corruption is visible and never silently repaired =="
chmod 0644 "$object"
printf 'corrupt\n' > "$object"

set +e
"$BIN" cache simd-dot >"$tmp/corrupt.out" 2>&1
rc=$?
set -e

[[ "$rc" -eq 13 ]]
grep -q 'corruption detected' "$tmp/corrupt.out"
grep -q 'refusing silent repair' "$tmp/corrupt.out"
[[ "$(cat "$object")" == "corrupt" ]]

echo "== XDG cache layout =="
unset ASMORY_CACHE_HOME
export XDG_CACHE_HOME="$tmp/xdg"
xdg_object="$XDG_CACHE_HOME/asmory/objects/sha256/$expected"
mkdir -p "$(dirname "$xdg_object")"
cp "$ROOT/build/packages/simd-dot-0.1.0.tar.gz" "$xdg_object"
chmod 0444 "$xdg_object"

xdg="$("$BIN" cache simd-dot)"
grep -q '^Cache hit$' <<<"$xdg"
grep -Fq "$xdg_object" <<<"$xdg"

echo "cache-smoke: ok"
