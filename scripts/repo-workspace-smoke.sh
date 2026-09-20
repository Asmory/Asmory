#!/usr/bin/env bash
set -euo pipefail
ROOT="${ASMORY_ROOT:-$PWD}"
cd "$ROOT"
export PATH="$ROOT/build:$PATH"
HELPER="$ROOT/build/asmory-workspace"
BIN="$ROOT/build/asmory"
[[ -x "$HELPER" && -x "$BIN" ]]

echo "== real repository workspace =="
"$HELPER" check
summary="$("$BIN" workspace)"
grep -q '^Asmory repository workspace' <<<"$summary"
grep -q '^simd-dot 0.1.0$' <<<"$summary"
grep -q 'path        examples/simd-dot' <<<"$summary"

echo "== package artifact is package-root only =="
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
"$HELPER" pack simd-dot "$tmp/simd-dot.tar.gz" >/dev/null
listing="$(tar -tzf "$tmp/simd-dot.tar.gz")"
if grep -q '^simd-dot/asmory.package.toml$' <<<"$listing"; then
  echo "repo-workspace-smoke: repository-control metadata leaked into source Artifact" >&2
  exit 1
fi
grep -q '^simd-dot/src/dot.S$' <<<"$listing"
[[ "$(sha256sum "$tmp/simd-dot.tar.gz" | awk '{print $1}')" == "891dc9efcca3337729f2adc6b74d3cb0bcc3549c482c24dcf5bc84bbc20f2862" ]]
! grep -qE '^(registry|cli|docs|site)/' <<<"$listing"

echo "== synthetic multi-package repository =="
repo="$tmp/repo"
mkdir -p "$repo/packages/alpha/src" "$repo/packages/beta/src"
cat >"$repo/asmory.workspace.toml" <<'EOF'
schema = 1

[workspace]
repository = "https://example.invalid/mono.git"
members = [
    "packages/alpha",
    "packages/beta",
]
EOF
cat >"$repo/packages/alpha/asmory.package.toml" <<'EOF'
schema = 1
[package]
name = "alpha"
version = "1.2.3"
EOF
cat >"$repo/packages/beta/asmory.package.toml" <<'EOF'
schema = 1
[package]
name = "beta"
version = "0.4.0"
EOF
printf '.section .text\n' >"$repo/packages/alpha/src/a.S"
printf '.section .text\n' >"$repo/packages/beta/src/b.S"
git -C "$repo" init -q
git -C "$repo" config user.email smoke@example.invalid
git -C "$repo" config user.name "Asmory Smoke"
git -C "$repo" add .
git -C "$repo" commit -qm initial

multi="$(cd "$repo" && "$HELPER" list)"
grep -q 'packages    2' <<<"$multi"
grep -q '^alpha 1.2.3$' <<<"$multi"
grep -q '^beta 0.4.0$' <<<"$multi"

prov="$(cd "$repo" && "$HELPER" provenance alpha)"
python3 - "$prov" <<'PY'
import json,re,sys
d=json.loads(sys.argv[1])
assert d["repository"] == "https://example.invalid/mono.git"
assert d["subdir"] == "packages/alpha"
assert re.fullmatch(r"[0-9a-f]{40}", d["commit"])
assert d["worktree_dirty"] is False
PY
(cd "$repo" && "$HELPER" publish-check alpha) >/dev/null

printf '\n# dirty alpha\n' >>"$repo/packages/alpha/src/a.S"
alpha="$(cd "$repo" && "$HELPER" provenance alpha)"
beta="$(cd "$repo" && "$HELPER" provenance beta)"
python3 - "$alpha" "$beta" <<'PY'
import json,sys
a=json.loads(sys.argv[1]); b=json.loads(sys.argv[2])
assert a["worktree_dirty"] is True
assert b["worktree_dirty"] is False
PY
set +e
(cd "$repo" && "$HELPER" publish-check alpha) >"$tmp/dirty.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 21 ]]
grep -q 'requires committed source' "$tmp/dirty.out"

echo "== package-root escape is rejected =="
printf '.include "../../../outside.inc"\n' >"$repo/packages/beta/src/bad.S"
printf 'x\n' >"$repo/outside.inc"
set +e
(cd "$repo" && "$HELPER" check) >"$tmp/escape.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 21 ]]
grep -q 'include escapes package root' "$tmp/escape.out"

echo "repo-workspace-smoke: ok"
