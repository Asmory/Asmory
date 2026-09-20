#!/usr/bin/env bash
set -euo pipefail

ORG="${ASMORY_ORG:-Asmory}"
REPO_NAME="${ASMORY_REPO:-Asmory}"
REPO="$ORG/$REPO_NAME"
ROOT="${ASMORY_ROOT:-$HOME/asm/Asmory}"

cd "$ROOT"

echo "===== Asmory GitHub bootstrap ====="
echo "repo:  $REPO"
echo "root:  $ROOT"
echo

echo "===== [1/9] GitHub auth ====="
gh auth status

echo "===== [2/9] organization ====="
if ! gh api "orgs/$ORG" >/dev/null 2>&1; then
  echo
  echo "GitHub Organization '$ORG' does not exist or is not accessible."
  echo "Opening organization creation page..."
  command -v xdg-open >/dev/null 2>&1 && \
    xdg-open "https://github.com/account/organizations/new" >/dev/null 2>&1 || true
  echo "Create organization '$ORG', then rerun this script."
  exit 2
fi

echo "===== [3/9] branch / local verification ====="
git branch -M main
make clean
make -j"$(nproc)"
make check
make smoke

echo "===== [4/9] commit ====="
git add .
if ! git diff --cached --quiet; then
  git commit -m "feat: bootstrap Asmory public project, CI and Pages"
else
  echo "No staged changes to commit."
fi

echo "===== [5/9] repository ====="
if gh repo view "$REPO" >/dev/null 2>&1; then
  if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "git@github.com:$REPO.git"
  else
    git remote add origin "git@github.com:$REPO.git"
  fi
  git push -u origin main
else
  gh repo create "$REPO" \
    --public \
    --source=. \
    --remote=origin \
    --push \
    --description "Assembly package registry with ISA-aware dependency and Variant resolution"
fi

echo "===== [6/9] repository metadata ====="
gh api \
  --method PATCH \
  "repos/$REPO" \
  -f description='Assembly package registry with ISA-aware dependency and Variant resolution' \
  -f homepage="https://${ORG,,}.github.io/$REPO_NAME/" \
  -F has_issues=true \
  -F has_projects=true \
  -F has_wiki=false \
  >/dev/null

echo "===== [7/9] topics ====="
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

echo "===== [8/9] GitHub Pages ====="
if gh api "repos/$REPO/pages" >/dev/null 2>&1; then
  echo "GitHub Pages already enabled."
else
  gh api \
    --method POST \
    "repos/$REPO/pages" \
    -f build_type=workflow \
    >/dev/null
fi

gh workflow run ci.yml --repo "$REPO" >/dev/null 2>&1 || true
gh workflow run pages.yml --repo "$REPO" >/dev/null 2>&1 || true

echo "===== [9/9] result ====="
echo
echo "Repository: https://github.com/$REPO"
echo "Pages:      https://${ORG,,}.github.io/$REPO_NAME/"
echo
gh run list --repo "$REPO" --limit 10
