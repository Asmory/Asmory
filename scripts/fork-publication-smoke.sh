#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$PWD}"
cd "$ROOT"

BIN="$ROOT/build/asmory"
STATE="$ROOT/build/asmory-state"
REGISTRY="$ROOT/build/asmory-registry"
BASE="http://127.0.0.1:18080"
LOG="$ROOT/build/asmory-fork-smoke-registry.log"

for x in \
  "$BIN" \
  "$STATE" \
  "$ROOT/build/asmory-fork" \
  "$ROOT/build/asmory-publish" \
  "$ROOT/build/asmory-workspace" \
  "$REGISTRY"
do
  [[ -x "$x" ]] || {
    echo "fork-smoke: missing executable: $x" >&2
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
git remote add origin https://example.invalid/project.git

"$BIN" init >/dev/null
"$BIN" add simd-dot >/dev/null

# Publication provenance requires an actual Git commit. Establish a clean
# project baseline before creating the new fork; the fork itself then becomes
# dirty/untracked Package state relative to that commit.
git add asm.toml asm.lock .asmory/.gitignore
git commit -qm 'baseline project workspace'

echo "== fork only the selected Package, never the upstream repository =="
printf '\n# local tuned fork\n' >> .asmory/deps/simd-dot/src/dot.S
source_tree="$("$STATE" tree-hash .asmory/deps/simd-dot)"

out="$("$BIN" fork simd-dot my-dot)"
grep -q '^Package fork created$' <<<"$out"
grep -q 'clone        not performed' <<<"$out"

[[ -f packages/my-dot/src/dot.S ]]
grep -q 'local tuned fork' packages/my-dot/src/dot.S
[[ -f packages/my-dot/asmory.package.toml ]]
[[ ! -e packages/my-dot/registry ]]
[[ ! -e packages/my-dot/cli ]]
[[ ! -e packages/my-dot/docs ]]

grep -q '^name = "my-dot"$' packages/my-dot/asmory.package.toml
grep -q '^version = "0.1.0"$' packages/my-dot/asmory.package.toml
grep -q '^kind = "asmory-fork"$' packages/my-dot/asmory.package.toml
grep -q '^package = "simd-dot"$' packages/my-dot/asmory.package.toml
grep -q "^source_tree_sha256 = \"$source_tree\"$" packages/my-dot/asmory.package.toml

grep -q '^    "packages/my-dot",$' asmory.workspace.toml

echo "== source dependency remains untouched after fork =="
[[ "$source_tree" == "$("$STATE" tree-hash .asmory/deps/simd-dot)" ]]
"$BIN" status | grep -q 'state       Modified'

echo "== new fork is Git-visible and has independent Package identity =="
if git check-ignore -q packages/my-dot/src/dot.S; then
  echo "fork-smoke: new Package is unexpectedly ignored" >&2
  exit 1
fi
git status --short --untracked-files=all | grep -q 'packages/my-dot/src/dot.S'

workspace="$("$BIN" workspace)"
grep -q '^my-dot 0.1.0$' <<<"$workspace"
grep -q 'path        packages/my-dot' <<<"$workspace"

echo "== publication prepare rejects dirty Package provenance =="
set +e
"$BIN" publish-prepare my-dot >"$tmp/dirty-publish.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 23 ]]
grep -q 'commit the fork/package before publication prepare' "$tmp/dirty-publish.out"

echo "== commit Package + workspace, then prepare deterministic candidate =="
git add asmory.workspace.toml packages/my-dot .asmory/.gitignore
git commit -qm 'add my-dot fork'

first="$("$BIN" publish-prepare my-dot)"
grep -q '^Publication candidate prepared$' <<<"$first"
grep -q 'remote       not uploaded' <<<"$first"

candidate=".asmory/.publish/my-dot/0.1.0/release-candidate.json"
artifact=".asmory/.publish/my-dot/0.1.0/my-dot-0.1.0.tar.gz"
[[ -f "$candidate" ]]
[[ -f "$artifact" ]]

candidate_sha="$(sha256sum "$candidate" | awk '{print $1}')"
artifact_sha="$(sha256sum "$artifact" | awk '{print $1}')"

python3 - "$candidate" "$artifact_sha" <<'PY'
import json, re, sys
p=sys.argv[1]
artifact_sha=sys.argv[2]
d=json.load(open(p))
assert d["schema"] == 1
assert d["kind"] == "asmory-release-candidate"
assert d["package"] == {"name":"my-dot","version":"0.1.0"}
assert d["artifact"]["sha256"] == artifact_sha
assert d["source"]["repository"] == "https://example.invalid/project.git"
assert d["source"]["subdir"] == "packages/my-dot"
assert d["source"]["worktree_dirty"] is False
assert re.fullmatch(r"[0-9a-f]{40}", d["source"]["commit"])
assert d["origin"]["kind"] == "asmory-fork"
assert d["origin"]["package"] == "simd-dot"
assert d["boundary"]["self_contained"] is True
assert d["boundary"]["package_manifest_in_artifact"] is False
PY

listing="$(tar -tzf "$artifact")"
grep -q '^my-dot/src/dot.S$' <<<"$listing"
if grep -q '^my-dot/asmory.package.toml$' <<<"$listing"; then
  echo "fork-smoke: repository identity manifest leaked into source Artifact" >&2
  exit 1
fi

echo "== prepare is deterministic and idempotent =="
second="$("$BIN" publish-prepare my-dot)"
grep -q '^Publication candidate already prepared$' <<<"$second"
[[ "$candidate_sha" == "$(sha256sum "$candidate" | awk '{print $1}')" ]]
[[ "$artifact_sha" == "$(sha256sum "$artifact" | awk '{print $1}')" ]]

echo "== sibling Package dirtiness does not dirty the fork Package =="
printf '\n# dirty old dependency only\n' >> .asmory/deps/simd-dot/src/dot.S
"$BIN" publish-prepare my-dot | grep -q '^Publication candidate already prepared$'

echo "== vendored source can also be forked as current project-owned bytes =="
project2="$tmp/vendor-project"
mkdir "$project2"
cd "$project2"
git init -q
git config user.email smoke@example.invalid
git config user.name "Asmory Smoke"
git remote add origin https://example.invalid/vendor-project.git

"$BIN" init >/dev/null
"$BIN" add simd-dot >/dev/null
"$BIN" vendor simd-dot >/dev/null
printf '\n# vendor-owned derivative\n' >> vendor/simd-dot/src/dot.S
vendor_tree="$("$STATE" tree-hash vendor/simd-dot)"

"$BIN" fork simd-dot vendor-dot >/dev/null
grep -q '^source_kind = "vendor"$' packages/vendor-dot/asmory.package.toml
grep -q "^source_tree_sha256 = \"$vendor_tree\"$" packages/vendor-dot/asmory.package.toml
grep -q 'vendor-owned derivative' packages/vendor-dot/src/dot.S

echo "== fork destination conflicts are fail-closed =="
before="$("$STATE" tree-hash vendor/simd-dot)"
set +e
"$BIN" fork simd-dot vendor-dot >"$tmp/conflict.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 22 ]]
grep -q 'fork destination already exists' "$tmp/conflict.out"
[[ "$before" == "$("$STATE" tree-hash vendor/simd-dot)" ]]

echo "fork-publication-smoke: ok"
