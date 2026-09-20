#!/usr/bin/env bash
set -euo pipefail

PORT="${ASMORY_PORT:-18080}"
BASE="http://127.0.0.1:${PORT}"
LOG="build/asmory-registry.log"
BIN="build/asmory-registry"

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
  if ss -ltn "sport = :$PORT" | awk 'NR>1{found=1} END{exit !found}'; then
    echo "smoke: port $PORT remains occupied" >&2
    ss -ltnp "sport = :$PORT" >&2 || true
    exit 1
  fi
fi

"$BIN" >"$LOG" 2>&1 &
PID=$!
cleanup(){ kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; }
trap cleanup EXIT

sleep 0.05
kill -0 "$PID" 2>/dev/null || {
  echo "smoke: newly built registry exited" >&2
  cat "$LOG" >&2 || true
  exit 1
}

for _ in $(seq 1 60); do
  curl -fsS "$BASE/" >/dev/null 2>&1 && break
  kill -0 "$PID" 2>/dev/null || exit 1
  sleep 0.05
done

check(){
  local path="$1" expected="$2" actual
  actual="$(curl -sS -o /tmp/asmory-smoke-body -w '%{http_code}' "$BASE$path")"
  printf '%-62s %s\n' "$path" "$actual"
  [[ "$actual" == "$expected" ]]
}

check / 200
check /packages 200
check /package/simd-dot 200
check /design 200
check /publishing 200
check /api/v1/packages 200
check /api/v1/packages/simd-dot 200
check /api/v1/packages/simd-dot/versions 200
check /api/v1/packages/simd-dot/0.1.0 200
check /api/v1/packages/simd-dot/0.1.0/evidence 200
check /api/v1/packages/simd-dot/0.1.0/semantics 200
check /api/v1/capabilities/math.dot.f32 200
check /api/v1/profiles/asmory/simd-dot-core/1.0.0 200
check /api/v1/profiles/asmory/simd-dot-strict/1.0.0 200
check /api/v1/packages/simd-dot/0.1.0/download 200
check /definitely-not-a-route 404

sem="$(curl -fsS "$BASE/api/v1/packages/simd-dot/0.1.0/semantics")"
python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["principles"]["facets_are_source_of_truth"] is True
assert d["principles"]["provider_is_semantic_identity"] is False
assert d["profile_matches"]["asmory/simd-dot-core@1.0.0"]["compatible"] is True
assert d["profile_matches"]["asmory/simd-dot-core@1.0.0"]["exact_semantic_identity"] is True
assert d["profile_matches"]["asmory/simd-dot-strict@1.0.0"]["compatible"] is False
assert len(d["semantic_fingerprint"]) == 64
' <<<"$sem"

cap="$(curl -fsS "$BASE/api/v1/capabilities/math.dot.f32")"
grep -q '"authority":"none"' <<<"$cap"

echo 'smoke: ok'
