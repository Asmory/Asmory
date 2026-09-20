#!/usr/bin/env bash
set -euo pipefail

PORT="${ASMORY_PORT:-18080}"
BASE="http://127.0.0.1:${PORT}"
LOG="build/asmory-registry.log"
BIN="build/asmory-registry"

# Prevent false-positive smoke tests against an old registry process.
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

ready=0
for _ in $(seq 1 60); do
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "smoke: current registry died during readiness wait" >&2
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

check(){
  local path="$1" expected="$2" actual
  actual="$(curl -sS -o /tmp/asmory-smoke-body -w '%{http_code}' "$BASE$path")"
  printf '%-52s %s\n' "$path" "$actual"
  [[ "$actual" == "$expected" ]]
}

check / 200
check /packages 200
check /package/simd-dot 200
check /design 200
check /publishing 200
check /static/app.css 200
check /static/app.js 200
check /api/v1/packages 200
check /api/v1/packages/simd-dot 200
check /api/v1/packages/simd-dot/versions 200
check /api/v1/packages/simd-dot/0.1.0 200
check /api/v1/packages/simd-dot/0.1.0/evidence 200
check /api/v1/packages/simd-dot/0.1.0/download 200
check /api/v1/package/simd-dot 200
check /download/simd-dot-0.1.0.tar.gz 200
check /definitely-not-a-route 404

curl -fsS "$BASE/api/v1/packages" | grep -q '"schema":2'
curl -fsS "$BASE/packages" | grep -q 'package-results'
curl -fsS "$BASE/package/simd-dot" | grep -q 'Variant matrix'
curl -fsS "$BASE/package/simd-dot" | grep -q 'Performance Evidence'
curl -fsS "$BASE/publishing" | grep -q 'immutable releases'
curl -fsS "$BASE/api/v1/packages/simd-dot" | grep -q '"latest_version":"0.1.0"'
curl -fsS "$BASE/api/v1/packages/simd-dot/versions" | grep -q '"version":"0.1.0"'

release_json="$(mktemp)"
evidence_json="$(mktemp)"
trap 'rm -f "$release_json" "$evidence_json"; cleanup' EXIT

curl -fsS "$BASE/api/v1/packages/simd-dot/0.1.0" >"$release_json"
curl -fsS "$BASE/api/v1/packages/simd-dot/0.1.0/evidence" >"$evidence_json"

api_sha="$(python3 - "$release_json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
print(d["release"]["artifacts"][0]["sha256"])
PY
)"

evidence_sha="$(python3 - "$evidence_json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d["status"] == "no-accepted-current-artifact-evidence"
assert d["accepted_records"] == []
assert d["policy"]["cross_machine_ranking"] is False
print(d["artifact"]["sha256"])
PY
)"

[[ "$api_sha" == "$evidence_sha" ]]

curl -fsS "$BASE/download/simd-dot-0.1.0.tar.gz" -o /tmp/simd-dot-0.1.0.tar.gz
tar -tzf /tmp/simd-dot-0.1.0.tar.gz | grep -q 'simd-dot/src/dot.S'
file_sha="$(sha256sum /tmp/simd-dot-0.1.0.tar.gz | awk '{print $1}')"
[[ "$api_sha" == "$file_sha" ]]

echo 'smoke: ok'
