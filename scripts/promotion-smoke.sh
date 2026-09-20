#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$PWD}"
cd "$ROOT"

BIN="$ROOT/build/asmory"
READ_REGISTRY="$ROOT/build/asmory-registry"
WRITE_REGISTRY="$ROOT/build/asmory-registry-write"
AUTH="$ROOT/build/asmory-registry-auth"
PROMOTE="$ROOT/build/asmory-promote"
BASE_READ="http://127.0.0.1:18080"
BASE_WRITE="http://127.0.0.1:18081"
READ_LOG="$ROOT/build/asmory-promotion-read.log"
WRITE_LOG="$ROOT/build/asmory-promotion-write.log"

for x in "$BIN" "$READ_REGISTRY" "$WRITE_REGISTRY" "$AUTH" "$PROMOTE"; do
  [[ -x "$x" ]] || {
    echo "promotion-smoke: missing executable: $x" >&2
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
      echo "promotion-smoke: port $port is already occupied" >&2
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

printf '\n# promoted fork\n' >> .asmory/deps/simd-dot/src/dot.S
"$BIN" fork simd-dot my-dot >/dev/null

echo "== fork rewrites source Package identity, not only repository metadata =="
grep -q '^name = "my-dot"$' packages/my-dot/asm.toml
grep -q '^version = "0.1.0"$' packages/my-dot/asm.toml
grep -q '^name = "my-dot"$' packages/my-dot/asmory.package.toml

git add asmory.workspace.toml packages/my-dot .asmory/.gitignore
git commit -qm 'add promotable my-dot fork'

echo "== authenticated staging =="
"$BIN" publish my-dot | grep -q '^Publication candidate uploaded$'

candidate=".asmory/.publish/my-dot/0.1.0/release-candidate.json"
artifact=".asmory/.publish/my-dot/0.1.0/my-dot-0.1.0.tar.gz"
candidate_sha="$(sha256sum "$candidate" | awk '{print $1}')"
artifact_sha="$(sha256sum "$artifact" | awk '{print $1}')"

echo "== promotion derives active Release contract from Artifact metadata =="
out="$("$BIN" promote my-dot)"
grep -q '^Release promoted$' <<<"$out"
grep -q 'state        promoted' <<<"$out"
grep -q 'resolvable   yes' <<<"$out"

active="$data_dir/active/projects/my-dot/releases/0.1.0.json"
[[ -f "$active" ]]

python3 - "$active" "$candidate_sha" "$artifact_sha" <<'PY'
import json,sys
record=json.load(open(sys.argv[1]))
candidate_sha=sys.argv[2]
artifact_sha=sys.argv[3]
assert record["registry"] == "Asmory"
assert record["schema"] == 5
assert record["project"] == "my-dot"
assert record["owner"] == "alice"
assert record["candidate_sha256"] == candidate_sha
assert record["resolvable"] is True
release=record["release"]
assert release["version"] == "0.1.0"
assert release["state"] == "active"
assert release["source"]["repository"] == "https://example.invalid/project.git"
assert release["source"]["subdir"] == "packages/my-dot"
assert release["capability"] == "math.dot.f32"
assert release["profile"] == "asmory/simd-dot-core@1.0.0"
assert release["semantic_fingerprint"] == "e9ebbaacbc67435c191c1add57a31b88489f62d105054a461f6c8429bb1cba7b"
assert release["canonical_semantics"]["capability"] == "math.dot.f32"
assert release["conformance"]["suite"] == "core-v1-basic"
assert release["conformance"]["execution"] == "not-registry-executed"
assert release["review"]["state"] == "unreviewed"
assert release["safety"]["state"] == "normal"
variant=release["variants"][0]
assert variant["id"] == "x86_64-avx2-generic"
assert variant["target"]["arch"] == "x86_64"
assert variant["target"]["os"] == "linux"
assert variant["target"]["object"] == "elf64"
assert variant["target"]["abi"] == "sysv64"
assert variant["target"]["isa"]["baseline"] == "x86-64-v3"
assert variant["target"]["isa"]["required"] == ["avx2","fma"]
assert variant["exports"][0]["symbol"] == "simd_dot_f32"
artifact=release["artifacts"][0]
assert artifact["sha256"] == artifact_sha
assert artifact["download"] == "/api/v1/packages/my-dot/0.1.0/download"
validation=release["promotion_validation"]
assert validation["server_derived_from_artifact"] is True
assert validation["semantic_fingerprint_recomputed"] is True
assert validation["code_execution"] is False
PY

echo "== active read API is public and resolver-facing =="
python3 - "$BASE_WRITE" "$artifact_sha" <<'PY'
import hashlib,http.client,json,sys
from urllib.parse import urlsplit
base=urlsplit(sys.argv[1])
artifact_sha=sys.argv[2]
def get(path):
    c=http.client.HTTPConnection(base.hostname,base.port,timeout=5)
    c.request("GET",path,headers={"Connection":"close"})
    r=c.getresponse(); body=r.read(); c.close()
    return r.status,body
status,body=get("/api/v1/packages/my-dot")
assert status == 200, (status,body)
project=json.loads(body)["project"]
assert project["name"] == "my-dot"
assert project["owner"] == "alice"
assert project["versions"] == ["0.1.0"]
status,body=get("/api/v1/packages/my-dot/versions")
assert status == 200, (status,body)
versions=json.loads(body)["versions"]
assert len(versions) == 1
summary=versions[0]
assert summary["version"] == "0.1.0"
assert summary["state"] == "active"
assert summary["variants"] == 1
assert summary["artifact_sha256"] == artifact_sha
assert summary["endpoint"] == "/api/v1/packages/my-dot/0.1.0"
status,body=get("/api/v1/packages/my-dot/0.1.0")
assert status == 200, (status,body)
release=json.loads(body)
assert release["resolvable"] is True
assert release["release"]["state"] == "active"
status,body=get("/api/v1/packages/my-dot/0.1.0/download")
assert status == 200
assert hashlib.sha256(body).hexdigest() == artifact_sha
PY

echo "== promotion is idempotent =="
again="$("$BIN" promote my-dot)"
grep -q 'state        reused' <<<"$again"
grep -q 'resolvable   yes' <<<"$again"

echo "== another authenticated publisher cannot promote owned Package =="
set +e
ASMORY_PUBLISH_TOKEN_FILE="$bob_token" "$BIN" promote my-dot >"$tmp/bob.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 26 ]]
grep -q 'Registry rejected promotion (403)' "$tmp/bob.out"

echo "== server rejects promotion when Artifact metadata disagrees with candidate identity =="
python3 - "$BASE_WRITE" "$alice_token" "$tmp" <<'PY'
import hashlib,http.client,io,json,pathlib,tarfile,sys
from urllib.parse import urlsplit
base=urlsplit(sys.argv[1])
token=pathlib.Path(sys.argv[2]).read_text().strip()
tmp=pathlib.Path(sys.argv[3])
name="bad-meta"; version="0.1.0"
asm='[package]\nname = "wrong-name"\nversion = "0.1.0"\n\n[semantics]\ncapability = "math.dot.f32"\ncontract = "asmory/simd-dot-core@1.0.0"\n\n[target]\narch = "x86_64"\nos = "linux"\nobject = "elf64"\nabi = "sysv64"\n\n[target.isa]\nbaseline = "x86-64-v3"\nrequired = ["avx2", "fma"]\noptional = []\n\n[toolchain]\nassembler = "gas"\nmin_version = "2.40"\nsyntax = "intel"\n\n[build]\nsources = ["src/dot.S"]\n\n[exports.dot_f32]\nsymbol = "simd_dot_f32"\nsection = ".text.simd_dot_f32"\ncalling_convention = "sysv64"\n'
sem='schema = 1\ncapability = "math.dot.f32"\nprofile = "asmory/simd-dot-core@1.0.0"\n[interface]\nshape = "dot-f32-v1"\nlogical_export = "dot_f32"\ncalling_convention = "sysv64"\n[requires.memory]\nalignment_min_bytes = 1\ninputs_readable = true\n[guarantees.memory]\ninputs_written = false\nout_of_bounds_access = false\n[guarantees.numeric]\nmode = "tolerance"\nabsolute_error_max = 0.000001\nrelative_error_max = 0.00001\nbit_exact = false\n[guarantees.determinism]\nlevel = "same-machine"\n[guarantees.side_effects]\nallowed = []\n'
suite='schema = 1\n[suite]\nid = "core-v1-basic"\nprofile = "asmory/simd-dot-core@1.0.0"\nrunner = "basic.S"\n\n[[suite.facets]]\npath = "interface.shape"\ntests = ["call-shape"]\n'
files={f"{name}/asm.toml":asm.encode(),f"{name}/semantics.toml":sem.encode(),f"{name}/conformance/suite.toml":suite.encode(),f"{name}/conformance/basic.S":b".section .text\n",f"{name}/src/dot.S":b".section .text\n"}
artifact=tmp/"bad-meta-0.1.0.tar.gz"
with tarfile.open(artifact,"w:gz") as tf:
    for path,data in files.items():
        info=tarfile.TarInfo(path); info.size=len(data); info.mode=0o644; info.mtime=0
        tf.addfile(info,io.BytesIO(data))
raw=artifact.read_bytes(); digest=hashlib.sha256(raw).hexdigest()
def request(method,path,body):
    c=http.client.HTTPConnection(base.hostname,base.port,timeout=5)
    c.request(method,path,body=body,headers={"Authorization":f"Bearer {token}","Content-Type":"application/json" if method=="POST" else "application/gzip","Content-Length":str(len(body)),"Connection":"close"})
    r=c.getresponse(); data=r.read(); c.close(); return r.status,data
status,body=request("PUT",f"/api/v1/staging/artifacts/sha256/{digest}",raw)
assert status == 201, (status,body)
candidate={"schema":1,"kind":"asmory-release-candidate","package":{"name":name,"version":version},"source":{"kind":"git","repository":"https://example.invalid/bad.git","commit":"a"*40,"subdir":"packages/bad-meta","worktree_dirty":False},"artifact":{"kind":"source","filename":f"{name}-{version}.tar.gz","sha256":digest,"size":len(raw)},"boundary":{"self_contained":True,"package_manifest_in_artifact":False},"origin":None}
candidate_raw=(json.dumps(candidate,sort_keys=True,separators=(",",":"))+"\n").encode()
status,body=request("POST","/api/v1/staging/releases",candidate_raw)
assert status == 201, (status,body)
candidate_sha=json.loads(body)["candidate_sha256"]
promotion={"schema":1,"kind":"asmory-promotion-request","package":name,"version":version,"candidate_sha256":candidate_sha}
promotion_raw=(json.dumps(promotion,sort_keys=True,separators=(",",":"))+"\n").encode()
status,body=request("POST","/api/v1/staging/promote",promotion_raw)
assert status == 422, (status,body)
assert b"Package identity does not match staged candidate" in body
PY
[[ ! -e "$data_dir/active/projects/bad-meta/releases/0.1.0.json" ]]

echo "== active Release survives write-service restart =="
kill "$WRITE_PID"
wait "$WRITE_PID" || true
WRITE_PID=""
ASMORY_WRITE_AUTH_FILE="$auth_db" ASMORY_WRITE_DATA_DIR="$data_dir" ASMORY_WRITE_HOST=127.0.0.1 ASMORY_WRITE_PORT=18081 "$WRITE_REGISTRY" >"$WRITE_LOG" 2>&1 &
WRITE_PID=$!
for _ in $(seq 1 80); do
  curl -fsS "$BASE_WRITE/healthz" >/dev/null 2>&1 && break
  sleep 0.05
done
curl -fsS "$BASE_WRITE/api/v1/packages/my-dot/0.1.0" | grep -q '"resolvable":true'

echo "promotion-smoke: ok"
