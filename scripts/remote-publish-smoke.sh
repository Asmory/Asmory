#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$PWD}"
cd "$ROOT"

BIN="$ROOT/build/asmory"
READ_REGISTRY="$ROOT/build/asmory-registry"
WRITE_REGISTRY="$ROOT/build/asmory-registry-write"
AUTH="$ROOT/build/asmory-registry-auth"
STATE="$ROOT/build/asmory-state"
BASE_READ="http://127.0.0.1:18080"
BASE_WRITE="http://127.0.0.1:18081"
READ_LOG="$ROOT/build/asmory-remote-publish-read.log"
WRITE_LOG="$ROOT/build/asmory-remote-publish-write.log"

for x in "$BIN" "$READ_REGISTRY" "$WRITE_REGISTRY" "$AUTH" "$STATE"; do
  [[ -x "$x" ]] || {
    echo "remote-publish-smoke: missing executable: $x" >&2
    exit 2
  }
done

mapfile -t stale_read < <(pgrep -x asmory-registry || true)
if ((${#stale_read[@]})); then
  kill "${stale_read[@]}" 2>/dev/null || true
  sleep 0.1
fi

if command -v ss >/dev/null 2>&1; then
  for port in 18080 18081; do
    if ss -ltn "sport = :$port" | awk 'NR>1{found=1} END{exit !found}'; then
      echo "remote-publish-smoke: port $port is already occupied" >&2
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
alice_token="$tmp/alice.token"
bob_token="$tmp/bob.token"
data_dir="$tmp/store"

"$AUTH" issue "$auth_db" alice "$alice_token" >/dev/null
"$AUTH" issue "$auth_db" bob "$bob_token" >/dev/null
[[ "$(stat -c '%a' "$auth_db")" == "600" ]]
[[ "$(stat -c '%a' "$alice_token")" == "600" ]]
[[ "$(stat -c '%a' "$bob_token")" == "600" ]]

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
export ASMORY_REGISTRY_URL="$BASE_READ"
export ASMORY_CACHE_HOME="$tmp/cache"
export ASMORY_PUBLISH_URL="$BASE_WRITE"
export ASMORY_PUBLISH_TOKEN_FILE="$alice_token"

project="$tmp/project"
mkdir "$project"
cd "$project"

git init -q
git config user.email smoke@example.invalid
git config user.name "Asmory Smoke"
git remote add origin https://example.invalid/project.git

"$BIN" init >/dev/null
"$BIN" add simd-dot >/dev/null
git add asm.toml asm.lock .asmory/.gitignore
git commit -qm 'baseline project workspace'

printf '\n# remotely staged fork\n' >> .asmory/deps/simd-dot/src/dot.S
"$BIN" fork simd-dot my-dot >/dev/null
git add asmory.workspace.toml packages/my-dot .asmory/.gitignore
git commit -qm 'add my-dot fork'

echo "== authenticated remote candidate upload =="
out="$("$BIN" publish my-dot)"
grep -q '^Publication candidate uploaded$' <<<"$out"
grep -q 'owner        alice' <<<"$out"
grep -q 'state        stored' <<<"$out"
grep -q 'resolvable   no' <<<"$out"

candidate=".asmory/.publish/my-dot/0.1.0/release-candidate.json"
artifact=".asmory/.publish/my-dot/0.1.0/my-dot-0.1.0.tar.gz"
artifact_sha="$(sha256sum "$artifact" | awk '{print $1}')"
candidate_sha="$(sha256sum "$candidate" | awk '{print $1}')"

[[ -f "$data_dir/objects/sha256/$artifact_sha" ]]
[[ -f "$data_dir/projects/my-dot/owner.json" ]]
[[ -f "$data_dir/projects/my-dot/candidates/0.1.0.json" ]]

python3 - "$data_dir/projects/my-dot/owner.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d == {"schema":1,"package":"my-dot","owner":"alice"}
PY

echo "== idempotent object + candidate publication =="
again="$("$BIN" publish my-dot)"
grep -q '^Publication candidate uploaded$' <<<"$again"
grep -q 'object       reused' <<<"$again"
grep -q 'state        reused' <<<"$again"

echo "== private staged read API returns exact candidate =="
python3 - "$BASE_WRITE" "$alice_token" "$candidate_sha" "$artifact_sha" <<'PY'
import hashlib,http.client,json,pathlib,sys
from urllib.parse import urlsplit

base=urlsplit(sys.argv[1])
token=pathlib.Path(sys.argv[2]).read_text().strip()
candidate_sha=sys.argv[3]
artifact_sha=sys.argv[4]

def req(method,path):
    c=http.client.HTTPConnection(base.hostname,base.port,timeout=5)
    c.request(method,path,headers={"Authorization":f"Bearer {token}","Connection":"close"})
    r=c.getresponse(); body=r.read(); c.close()
    return r.status,body

status,body=req("GET","/api/v1/staging/packages/my-dot/0.1.0")
assert status == 200, (status,body)
record=json.loads(body)
assert record["state"] == "staged"
assert record["resolvable"] is False
assert record["owner"] == "alice"
assert record["candidate_sha256"] == candidate_sha
assert record["artifact_sha256"] == artifact_sha

status,body=req("GET","/api/v1/staging/packages/my-dot/0.1.0/download")
assert status == 200
assert hashlib.sha256(body).hexdigest() == artifact_sha
PY

echo "== invalid token is rejected before ownership mutation =="
bad_token="$tmp/bad.token"
printf 'this-is-a-deliberately-invalid-publication-token-1234567890\n' >"$bad_token"
chmod 0600 "$bad_token"
set +e
ASMORY_PUBLISH_TOKEN_FILE="$bad_token" "$BIN" publish my-dot >"$tmp/bad-token.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 24 ]]
grep -q 'Registry rejected Artifact (401)' "$tmp/bad-token.out"

echo "== insecure token permissions are rejected client-side =="
chmod 0644 "$alice_token"
set +e
"$BIN" publish my-dot >"$tmp/perms.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 24 ]]
grep -q 'must not be readable/writable by group or others' "$tmp/perms.out"
chmod 0600 "$alice_token"

echo "== external plaintext HTTP is rejected before transport =="
set +e
ASMORY_PUBLISH_URL="http://192.0.2.1:18081" \
"$BIN" publish my-dot >"$tmp/plain.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 24 ]]
grep -q 'plaintext HTTP publication is allowed only for loopback' "$tmp/plain.out"

echo "== different authenticated owner cannot publish same Package =="
python3 - "$BASE_WRITE" "$bob_token" "$candidate" <<'PY'
import http.client,pathlib,sys
from urllib.parse import urlsplit
base=urlsplit(sys.argv[1])
token=pathlib.Path(sys.argv[2]).read_text().strip()
body=pathlib.Path(sys.argv[3]).read_bytes()
c=http.client.HTTPConnection(base.hostname,base.port,timeout=5)
c.request(
    "POST",
    "/api/v1/staging/releases",
    body=body,
    headers={
        "Authorization":f"Bearer {token}",
        "Content-Type":"application/json",
        "Content-Length":str(len(body)),
        "Connection":"close",
    },
)
r=c.getresponse(); data=r.read(); c.close()
assert r.status == 403, (r.status,data)
PY

echo "== same owner cannot rewrite immutable staged version =="
python3 - "$BASE_WRITE" "$alice_token" "$candidate" <<'PY'
import http.client,json,pathlib,sys
from urllib.parse import urlsplit
base=urlsplit(sys.argv[1])
token=pathlib.Path(sys.argv[2]).read_text().strip()
obj=json.loads(pathlib.Path(sys.argv[3]).read_text())
commit=obj["source"]["commit"]
obj["source"]["commit"]=("0" if commit[0] != "0" else "1") + commit[1:]
body=(json.dumps(obj,sort_keys=True,separators=(",",":"))+"\n").encode()
c=http.client.HTTPConnection(base.hostname,base.port,timeout=5)
c.request(
    "POST",
    "/api/v1/staging/releases",
    body=body,
    headers={
        "Authorization":f"Bearer {token}",
        "Content-Type":"application/json",
        "Content-Length":str(len(body)),
        "Connection":"close",
    },
)
r=c.getresponse(); data=r.read(); c.close()
assert r.status == 409, (r.status,data)
PY

echo "== Artifact digest mismatch is fail-closed =="
python3 - "$BASE_WRITE" "$alice_token" <<'PY'
import http.client,pathlib,sys
from urllib.parse import urlsplit
base=urlsplit(sys.argv[1])
token=pathlib.Path(sys.argv[2]).read_text().strip()
body=b"not-the-declared-object"
digest="0"*64
c=http.client.HTTPConnection(base.hostname,base.port,timeout=5)
c.request(
    "PUT",
    f"/api/v1/staging/artifacts/sha256/{digest}",
    body=body,
    headers={
        "Authorization":f"Bearer {token}",
        "Content-Type":"application/gzip",
        "Content-Length":str(len(body)),
        "Connection":"close",
    },
)
r=c.getresponse(); data=r.read(); c.close()
assert r.status == 422, (r.status,data)
PY
[[ ! -e "$data_dir/objects/sha256/$(printf '0%.0s' {1..64})" ]]

echo "== staged state survives write-service restart =="
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

after="$("$BIN" publish my-dot)"
grep -q 'object       reused' <<<"$after"
grep -q 'state        reused' <<<"$after"

echo "remote-publish-smoke: ok"
