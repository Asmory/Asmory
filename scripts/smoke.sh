#!/usr/bin/env bash
set -euo pipefail
PORT="${ASMORY_PORT:-18080}"
BASE="http://127.0.0.1:${PORT}"
LOG="build/asmory-registry.log"
BIN="build/asmory-registry"

"$BIN" >"$LOG" 2>&1 &
PID=$!
cleanup(){ kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; }
trap cleanup EXIT

for _ in $(seq 1 40); do
  if curl -fsS "$BASE/" >/dev/null 2>&1; then break; fi
  sleep 0.05
done

check(){
  local path="$1" expected="$2" actual
  actual="$(curl -sS -o /tmp/asmory-smoke-body -w '%{http_code}' "$BASE$path")"
  printf '%-42s %s\n' "$path" "$actual"
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
check /api/v1/packages/simd-dot/0.1.0/download 200
check /api/v1/package/simd-dot 200
check /download/simd-dot-0.1.0.tar.gz 200
check /definitely-not-a-route 404

curl -fsS "$BASE/api/v1/packages" | grep -q '"schema":2'
curl -fsS "$BASE/packages" | grep -q 'package-results'
curl -fsS "$BASE/package/simd-dot" | grep -q 'Variant matrix'
curl -fsS "$BASE/publishing" | grep -q 'immutable releases'
curl -fsS "$BASE/api/v1/packages/simd-dot" | grep -q '"latest_version":"0.1.0"'
curl -fsS "$BASE/api/v1/packages/simd-dot/versions" | grep -q '"version":"0.1.0"'
api_sha="$(curl -fsS "$BASE/api/v1/packages/simd-dot/0.1.0" | python3 -c 'import json,sys; print(json.load(sys.stdin)["release"]["artifacts"][0]["sha256"])')"
curl -fsS "$BASE/download/simd-dot-0.1.0.tar.gz" -o /tmp/simd-dot-0.1.0.tar.gz
tar -tzf /tmp/simd-dot-0.1.0.tar.gz | grep -q 'simd-dot/src/dot.S'
file_sha="$(sha256sum /tmp/simd-dot-0.1.0.tar.gz | awk '{print $1}')"
[[ "$api_sha" == "$file_sha" ]]
echo 'smoke: ok'
