#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$PWD}"
cd "$ROOT"

BIN="$ROOT/build/asmory"
READ_REGISTRY="$ROOT/build/asmory-registry"
WRITE_REGISTRY="$ROOT/build/asmory-registry-write"
AUTH="$ROOT/build/asmory-registry-auth"
SEMANTIC_RESOLVER="$ROOT/build/asmory-semantic-resolver"
BASE_READ="http://127.0.0.1:18080"
BASE_WRITE="http://127.0.0.1:18081"
READ_LOG="$ROOT/build/asmory-semantic-provider-read.log"
WRITE_LOG="$ROOT/build/asmory-semantic-provider-write.log"
CORE_PROFILE="$ROOT/examples/simd-dot/profiles/core-v1.toml"
STRICT_PROFILE="$ROOT/examples/simd-dot/profiles/strict-v1.toml"

for x in \
  "$BIN" \
  "$READ_REGISTRY" \
  "$WRITE_REGISTRY" \
  "$AUTH" \
  "$ROOT/build/asmory-remote" \
  "$SEMANTIC_RESOLVER"
do
  [[ -x "$x" ]] || {
    echo "semantic-provider-smoke: missing executable: $x" >&2
    exit 2
  }
done

[[ -f "$ROOT/build/semantic_model.py" ]] || {
  echo "semantic-provider-smoke: missing build/semantic_model.py" >&2
  exit 2
}

mapfile -t stale < <(pgrep -x asmory-registry || true)
if ((${#stale[@]})); then
  kill "${stale[@]}" 2>/dev/null || true
  sleep 0.1
fi

if command -v ss >/dev/null 2>&1; then
  for port in 18080 18081; do
    if ss -ltn "sport = :$port" | awk 'NR>1{found=1} END{exit !found}'; then
      echo "semantic-provider-smoke: port $port is already occupied" >&2
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
export ASMORY_PUBLISH_URL="$BASE_WRITE"
export ASMORY_PUBLISH_TOKEN_FILE="$token"

echo "== publish first arbitrary Provider for one Capability =="
publisher="$tmp/publisher"
mkdir "$publisher"
cd "$publisher"

git init -q
git config user.email smoke@example.invalid
git config user.name "Asmory Smoke"
git remote add origin https://example.invalid/providers.git

ASMORY_REGISTRY_URL="$BASE_READ" "$BIN" init >/dev/null
ASMORY_REGISTRY_URL="$BASE_READ" "$BIN" add simd-dot >/dev/null
git add asm.toml asm.lock .asmory/.gitignore
git commit -qm 'provider workspace baseline'

printf '\n# provider implementation A\n' >> .asmory/deps/simd-dot/src/dot.S
"$BIN" fork simd-dot provider-a >/dev/null
git add asmory.workspace.toml packages/provider-a .asmory/.gitignore
git commit -qm 'add provider-a'

"$BIN" publish provider-a >/dev/null
"$BIN" promote provider-a >/dev/null

semantic_index="$data_dir/active/semantic-index.json"
[[ -f "$semantic_index" ]]

echo "== semantic index has Capability, fingerprint and Facet inverted keys =="
python3 - "$semantic_index" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d["kind"] == "asmory-semantic-provider-index"
assert d["schema"] == 1

providers=d["providers"]
assert sorted(providers) == ["provider-a@0.1.0"]

cap=d["by_capability"]["math.dot.f32"]
assert cap == ["provider-a@0.1.0"]

fp="e9ebbaacbc67435c191c1add57a31b88489f62d105054a461f6c8429bb1cba7b"
assert d["by_fingerprint"][fp] == ["provider-a@0.1.0"]

shape='interface.shape="dot-f32-v1"'
logical='interface.logical_export="dot_f32"'
calling='interface.calling_convention="sysv64"'
for key in (shape,logical,calling):
    assert d["by_facet"][key] == ["provider-a@0.1.0"]
PY

curl -fsS "$BASE_WRITE/api/v1/capabilities/math.dot.f32/providers?limit=100" \
  | grep -q '"package":"provider-a"'

echo "== Profile resolver uses Facet prefilter + directional semantic match + Machine Contract =="
consumer="$tmp/consumer-one"
mkdir "$consumer"
cd "$consumer"

export ASMORY_REGISTRY_URL="$BASE_WRITE"
"$BIN" init >/dev/null

providers="$("$BIN" remote providers math.dot.f32)"
grep -q '^Providers for math.dot.f32$' <<<"$providers"
grep -q 'provider-a' <<<"$providers"

matched="$("$BIN" remote match-profile "$CORE_PROFILE")"
grep -q '^Semantic Provider Resolution$' <<<"$matched"
grep -q '^ACCEPT provider-a@0.1.0 semantic=exact variant=x86_64-avx2-generic$' <<<"$matched"
grep -q '^accepted: 1$' <<<"$matched"

set +e
strict="$("$BIN" remote match-profile "$STRICT_PROFILE" 2>&1)"
strict_rc=$?
set -e
[[ "$strict_rc" -eq 5 ]]
grep -q '^REJECT provider-a@0.1.0 semantic=' <<<"$strict"
grep -q 'numeric.absolute_error_max' <<<"$strict"
grep -q '^accepted: 0$' <<<"$strict"

echo "== unique compatible semantic Provider can enter normal dependency lifecycle =="
"$BIN" remote add-profile "$CORE_PROFILE" >/dev/null
[[ -f .asmory/deps/provider-a/asm.toml ]]
grep -q '^name = "provider-a"$' .asmory/deps/provider-a/asm.toml
grep -q '^name = "provider-a"$' asm.lock
grep -q '^semantic_fingerprint = "e9ebbaacbc67435c191c1add57a31b88489f62d105054a461f6c8429bb1cba7b"$' asm.lock
"$BIN" status | grep -q 'state       Exact'

echo "== second independently published Provider joins same semantic island =="
cd "$publisher"
"$BIN" fork simd-dot provider-b >/dev/null
git add asmory.workspace.toml packages/provider-b .asmory/.gitignore
git commit -qm 'add provider-b'
"$BIN" publish provider-b >/dev/null
"$BIN" promote provider-b >/dev/null

echo "== staged-only Provider never leaks into semantic Provider index =="
"$BIN" fork simd-dot provider-staged >/dev/null
git add asmory.workspace.toml packages/provider-staged .asmory/.gitignore
git commit -qm 'add provider-staged'
"$BIN" publish provider-staged >/dev/null

python3 - "$semantic_index" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
ids=sorted(d["by_capability"]["math.dot.f32"])
assert ids == ["provider-a@0.1.0","provider-b@0.1.0"]
assert "provider-staged@0.1.0" not in d["providers"]

fp="e9ebbaacbc67435c191c1add57a31b88489f62d105054a461f6c8429bb1cba7b"
assert sorted(d["by_fingerprint"][fp]) == ids
assert sorted(d["by_facet"]['interface.shape="dot-f32-v1"']) == ids
PY

echo "== semantic resolution refuses arbitrary winner without a ranking policy =="
consumer2="$tmp/consumer-two"
mkdir "$consumer2"
cd "$consumer2"
"$BIN" init >/dev/null

matched="$("$BIN" remote match-profile "$CORE_PROFILE")"
grep -q '^ACCEPT provider-a@0.1.0 ' <<<"$matched"
grep -q '^ACCEPT provider-b@0.1.0 ' <<<"$matched"
grep -q '^accepted: 2$' <<<"$matched"

set +e
"$BIN" remote add-profile "$CORE_PROFILE" >"$tmp/ambiguous.out" 2>&1
ambiguous_rc=$?
set -e
[[ "$ambiguous_rc" -eq 28 ]]
grep -q 'semantic request is ambiguous across 2 compatible Providers' "$tmp/ambiguous.out"

# No dependency was silently selected.
! grep -q '^name = "provider-a"$' asm.lock
! grep -q '^name = "provider-b"$' asm.lock

echo "== exact Facet query narrows provider candidates server-side =="
python3 - "$BASE_WRITE" <<'PY'
import http.client,json,sys
from urllib.parse import urlencode,urlsplit

base=urlsplit(sys.argv[1])
query=urlencode({
    "capability":"math.dot.f32",
    "facet":[
        'interface.shape="dot-f32-v1"',
        'interface.logical_export="dot_f32"',
        'interface.calling_convention="sysv64"',
    ],
    "limit":"100",
},doseq=True)

c=http.client.HTTPConnection(base.hostname,base.port,timeout=5)
c.request("GET","/api/v1/semantic/providers?"+query,headers={"Connection":"close"})
r=c.getresponse(); body=r.read(); c.close()
assert r.status == 200, (r.status,body)
data=json.loads(body)
assert [p["package"] for p in data["providers"]] == ["provider-a","provider-b"]
assert data["prefilter"]["facets"] == 3
PY

echo "== semantic index is derived/rebuilt across service restart =="
# Registry index files are intentionally published read-only (0444).
# Remove the derived inode from its writable parent directory before
# creating malformed replacement bytes for restart/rebuild testing.
rm -f "$semantic_index"
printf '{"corrupt":true}\n' >"$semantic_index"

kill "$WRITE_PID"
wait "$WRITE_PID" || true
WRITE_PID=""

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

python3 - "$semantic_index" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d["kind"] == "asmory-semantic-provider-index"
assert sorted(d["providers"]) == ["provider-a@0.1.0","provider-b@0.1.0"]
PY

"$BIN" remote providers math.dot.f32 | grep -q 'provider-b'

echo "semantic-provider-smoke: ok"
