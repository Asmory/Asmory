#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$PWD}"
cd "$ROOT"

BIN="$ROOT/build/asmory"
READ_REGISTRY="$ROOT/build/asmory-registry"
WRITE_REGISTRY="$ROOT/build/asmory-registry-write"
AUTH="$ROOT/build/asmory-registry-auth"
BASE_READ="http://127.0.0.1:18080"
BASE_WRITE="http://127.0.0.1:18081"
READ_LOG="$ROOT/build/asmory-remote-index-read.log"
WRITE_LOG="$ROOT/build/asmory-remote-index-write.log"

for x in \
  "$BIN" \
  "$READ_REGISTRY" \
  "$WRITE_REGISTRY" \
  "$AUTH" \
  "$ROOT/build/asmory-remote" \
  "$ROOT/build/asmory-promote"
do
  [[ -x "$x" ]] || {
    echo "remote-index-smoke: missing executable: $x" >&2
    exit 2
  }
done

mapfile -t stale < <(pgrep -x asmory-registry || true)
if ((${#stale[@]})); then
  kill "${stale[@]}" 2>/dev/null || true
  sleep 0.1
fi

if command -v ss >/dev/null 2>&1; then
  for port in 18080 18081; do
    if ss -ltn "sport = :$port" | awk 'NR>1{found=1} END{exit !found}'; then
      echo "remote-index-smoke: port $port is already occupied" >&2
      ss -ltnp "sport = :$port" >&2 || true
      exit 1
    fi
  done
fi

tmp="$(mktemp -d)"
READ_PID=""
WRITE_PID=""

cleanup() {
  if [[ -n "$WRITE_PID" ]]; then
    kill "$WRITE_PID" 2>/dev/null || true
    wait "$WRITE_PID" 2>/dev/null || true
  fi
  if [[ -n "$READ_PID" ]]; then
    kill "$READ_PID" 2>/dev/null || true
    wait "$READ_PID" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

auth_db="$tmp/auth.json"
token="$tmp/alice.token"
data_dir="$tmp/store"

"$AUTH" issue "$auth_db" alice "$token" >/dev/null

"$READ_REGISTRY" >"$READ_LOG" 2>&1 &
READ_PID=$!

ASMORY_WRITE_AUTH_FILE="$auth_db" \
ASMORY_WRITE_DATA_DIR="$data_dir" \
ASMORY_WRITE_HOST=127.0.0.1 \
ASMORY_WRITE_PORT=18081 \
"$WRITE_REGISTRY" >"$WRITE_LOG" 2>&1 &
WRITE_PID=$!

for _ in $(seq 1 80); do
  curl -fsS "$BASE_READ/" >/dev/null 2>&1 && break
  kill -0 "$READ_PID" 2>/dev/null || {
    cat "$READ_LOG" >&2 || true
    exit 1
  }
  sleep 0.05
done

for _ in $(seq 1 80); do
  curl -fsS "$BASE_WRITE/healthz" >/dev/null 2>&1 && break
  kill -0 "$WRITE_PID" 2>/dev/null || {
    cat "$WRITE_LOG" >&2 || true
    exit 1
  }
  sleep 0.05
done

export PATH="$ROOT/build:$PATH"
export ASMORY_CACHE_HOME="$tmp/cache"

echo "== publish one active Package and one staged-only Package =="
publisher="$tmp/publisher"
mkdir "$publisher"
cd "$publisher"

git init -q
git config user.email smoke@example.invalid
git config user.name "Asmory Smoke"
git remote add origin https://example.invalid/publisher.git

ASMORY_REGISTRY_URL="$BASE_READ" "$BIN" init >/dev/null
ASMORY_REGISTRY_URL="$BASE_READ" "$BIN" add simd-dot >/dev/null
git add asm.toml asm.lock .asmory/.gitignore
git commit -qm 'publisher baseline'

printf '\n# remote consumer roundtrip fork\n' >> .asmory/deps/simd-dot/src/dot.S
"$BIN" fork simd-dot my-dot >/dev/null
git add asmory.workspace.toml packages/my-dot .asmory/.gitignore
git commit -qm 'add my-dot'

ASMORY_PUBLISH_URL="$BASE_WRITE" \
ASMORY_PUBLISH_TOKEN_FILE="$token" \
"$BIN" publish my-dot >/dev/null

ASMORY_PUBLISH_URL="$BASE_WRITE" \
ASMORY_PUBLISH_TOKEN_FILE="$token" \
"$BIN" promote my-dot >/dev/null

"$BIN" fork simd-dot staged-only >/dev/null
git add asmory.workspace.toml packages/staged-only .asmory/.gitignore
git commit -qm 'add staged-only'

ASMORY_PUBLISH_URL="$BASE_WRITE" \
ASMORY_PUBLISH_TOKEN_FILE="$token" \
"$BIN" publish staged-only >/dev/null

echo "== persistent active search index contains only promoted Packages =="
[[ -f "$data_dir/active/index.json" ]]
python3 - "$data_dir/active/index.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d["kind"] == "asmory-active-index"
names=[p["name"] for p in d["packages"]]
assert "my-dot" in names
assert "staged-only" not in names
PY

curl -fsS "$BASE_WRITE/api/v1/packages?q=my-dot&limit=10" \
  | grep -q '"name":"my-dot"'

if curl -fsS "$BASE_WRITE/api/v1/packages?q=staged-only&limit=10" \
  | grep -q '"name":"staged-only"'; then
  echo "remote-index-smoke: staged-only Package leaked into active index" >&2
  exit 1
fi

curl -fsS \
  "$BASE_WRITE/api/v1/packages?capability=math.dot.f32&arch=x86_64&limit=10" \
  | grep -q '"name":"my-dot"'

curl -fsS "$BASE_WRITE/api/v1/packages/my-dot/versions" \
  | grep -q '"version":"0.1.0"'

echo "== normal CLI discovers/resolves promoted arbitrary Package =="
consumer="$tmp/consumer"
mkdir "$consumer"
cd "$consumer"

export ASMORY_REGISTRY_URL="$BASE_WRITE"

"$BIN" init >/dev/null

search="$("$BIN" search my-dot)"
grep -q '^Remote Asmory index$' <<<"$search"
grep -q 'my-dot' <<<"$search"

info="$("$BIN" info my-dot)"
grep -q '^my-dot 0.1.0$' <<<"$info"
grep -q 'owner.*alice' <<<"$info"
grep -q 'capability.*math.dot.f32' <<<"$info"

versions="$("$BIN" versions my-dot)"
grep -q '^my-dot active Releases$' <<<"$versions"
grep -q '^0.1.0' <<<"$versions"

resolved="$("$BIN" resolve my-dot)"
grep -q '^Resolved remote dependency$' <<<"$resolved"
grep -q 'compatibility yes' <<<"$resolved"

explicit="$("$BIN" remote resolve my-dot)"
grep -q '^Resolved remote dependency$' <<<"$explicit"

echo "== normal asmory add consumes promoted Package through active Registry =="
"$BIN" add my-dot >/dev/null

[[ -f .asmory/deps/my-dot/asm.toml ]]
grep -q '^name = "my-dot"$' .asmory/deps/my-dot/asm.toml
grep -q '^name = "my-dot"$' asm.lock
grep -q '^provider = "alice"$' asm.lock
grep -q '^source_kind = "registry"$' asm.lock

"$BIN" status | grep -q 'state       Exact'

echo "== promoted dependency joins the existing offline lifecycle =="
printf '\n# consumer edit\n' >> .asmory/deps/my-dot/src/dot.S
"$BIN" status | grep -q 'state       Modified'

kill "$WRITE_PID"
wait "$WRITE_PID" || true
WRITE_PID=""

"$BIN" restore my-dot >/dev/null
"$BIN" status | grep -q 'state       Exact'

echo "== restart rebuilds/retains the persistent active index =="
ASMORY_WRITE_AUTH_FILE="$auth_db" \
ASMORY_WRITE_DATA_DIR="$data_dir" \
ASMORY_WRITE_HOST=127.0.0.1 \
ASMORY_WRITE_PORT=18081 \
"$WRITE_REGISTRY" >"$WRITE_LOG" 2>&1 &
WRITE_PID=$!

for _ in $(seq 1 80); do
  curl -fsS "$BASE_WRITE/healthz" >/dev/null 2>&1 && break
  sleep 0.05
done

"$BIN" search my-dot | grep -q 'my-dot'
curl -fsS "$BASE_WRITE/api/v1/packages/my-dot/0.1.0/download" \
  -o "$tmp/restart-artifact.tar.gz"
sha256sum "$tmp/restart-artifact.tar.gz" \
  | grep -q "$(awk -F' = ' '/^artifact_sha256 = / {gsub(/"/,"",$2); print $2}' asm.lock)"

echo "remote-index-smoke: ok"
