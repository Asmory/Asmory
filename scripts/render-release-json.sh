#!/usr/bin/env bash
set -euo pipefail
ARCHIVE="${1:?archive required}"
TEMPLATE="${2:?template required}"
OUTPUT="${3:?output required}"
sha="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
size="$(wc -c < "$ARCHIVE" | tr -d '[:space:]')"
sed -e "s/@SHA256@/$sha/g" -e "s/@SIZE@/$size/g" "$TEMPLATE" > "$OUTPUT"
grep -q "\"sha256\":\"$sha\"" "$OUTPUT"
grep -q "\"size\":$size" "$OUTPUT"
