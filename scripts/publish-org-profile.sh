#!/usr/bin/env bash
set -euo pipefail

ORG="${ASMORY_ORG:-Asmory}"
ROOT="${ASMORY_ROOT:-$HOME/asm/Asmory}"
REPO="$ORG/.github"
PROFILE="$ROOT/org/profile/README.md"

cd "$ROOT"
gh auth status >/dev/null

if ! gh repo view "$REPO" >/dev/null 2>&1; then
  gh repo create "$REPO" --public --description "Asmory organization profile and community health files"
fi

CONTENT="$(base64 -w0 "$PROFILE")"
SHA="$(gh api "repos/$REPO/contents/profile/README.md" --jq .sha 2>/dev/null || true)"

if [[ -n "$SHA" ]]; then
  gh api --method PUT "repos/$REPO/contents/profile/README.md" \
    -f message='docs: update Asmory organization profile' \
    -f content="$CONTENT" \
    -f sha="$SHA" >/dev/null
else
  gh api --method PUT "repos/$REPO/contents/profile/README.md" \
    -f message='docs: publish Asmory organization profile' \
    -f content="$CONTENT" >/dev/null
fi

echo "organization profile published: https://github.com/$ORG"
