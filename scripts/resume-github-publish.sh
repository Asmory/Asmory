#!/usr/bin/env bash
set -euo pipefail

ORG="${ASMORY_ORG:-Asmory}"
REPO_NAME="${ASMORY_REPO:-Asmory}"
REPO="$ORG/$REPO_NAME"
ROOT="${ASMORY_ROOT:-$HOME/asm/Asmory}"

cd "$ROOT"

echo "===== Asmory GitHub publish resume ====="
echo "repo: $REPO"
echo

echo "===== [1/6] verify auth / repo ====="
gh auth status
gh repo view "$REPO" >/dev/null

echo "===== [2/6] set GitHub topics (20 max) ====="
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "repos/$REPO/topics" \
  --input - <<'JSON'
{
  "names": [
    "assembly",
    "assembly-language",
    "x86-64",
    "aarch64",
    "riscv",
    "simd",
    "avx2",
    "avx512",
    "sve",
    "riscv-vector",
    "isa",
    "abi",
    "elf",
    "linker",
    "package-manager",
    "package-registry",
    "high-performance-computing",
    "systems-programming",
    "low-level",
    "ai-coding"
  ]
}
JSON

echo "===== [3/6] enable GitHub Pages (Actions source) ====="
if gh api "repos/$REPO/pages" >/dev/null 2>&1; then
  echo "GitHub Pages already enabled."
else
  gh api \
    --method POST \
    "repos/$REPO/pages" \
    -f build_type=workflow \
    >/dev/null
  echo "GitHub Pages enabled."
fi

echo "===== [4/6] persist corrected publish script ====="
git add scripts/publish-github.sh scripts/resume-github-publish.sh 2>/dev/null || true
if ! git diff --cached --quiet; then
  git commit -m "fix: respect GitHub topic limit and resume Pages setup"
  git push
else
  echo "No local script changes to commit."
fi

echo "===== [5/6] run workflows ====="
gh workflow run ci.yml --repo "$REPO" >/dev/null 2>&1 || true
gh workflow run pages.yml --repo "$REPO"

echo "===== [6/6] status ====="
echo
echo "Repository: https://github.com/$REPO"
echo "Pages:      https://${ORG,,}.github.io/$REPO_NAME/"
echo
gh run list --repo "$REPO" --limit 10
