#!/usr/bin/env bash
set -euo pipefail

input="${1:?release json required}"
output="${2:?output include required}"

python3 - "$input" "$output" <<'PY'
import json
from pathlib import Path
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

data = json.loads(src.read_text())
r = data["release"]

artifact = next(a for a in r["artifacts"] if a["kind"] == "source")
stable = next(v for v in r["variants"] if v.get("stability") == "stable")
experimental = next(
    (v for v in r["variants"] if v.get("stability") == "experimental"),
    stable,
)

required = stable["target"]["isa"]["required"]
review = r.get("review", {})
safety = r.get("safety", {})
advisories = safety.get("advisories", [])

fields = {
    "registry_pkg_name": data["project"],
    "registry_version": r["version"],
    "registry_provider": r["provider"],
    "registry_capability": r["capability"],
    "registry_profile": r["profile"],
    "registry_artifact_policy": r["artifact_policy"],
    "registry_dependency_kind": r["dependency_model"]["kind"],
    "registry_variant_primary": stable["id"],
    "registry_variant_alternate": experimental["id"],
    "registry_required_isa": ", ".join(required),
    "registry_artifact_kind": artifact["kind"],
    "registry_artifact_filename": artifact["filename"],
    "registry_artifact_sha256": artifact["sha256"],
    "registry_review_state": review.get("state", "unknown"),
    "registry_reviewed_anchor": "yes" if review.get("reviewed_anchor") else "no",
    "registry_safety_state": safety.get("state", "unknown"),
    "registry_advisories": ", ".join(advisories) if advisories else "none known",
}

def gas_string(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
    )

lines = [
    "# Generated from the exact rendered Registry Release JSON.",
    "# Do not edit by hand.",
]
for label, value in fields.items():
    lines.append(f'{label}: .asciz "{gas_string(str(value))}"')

dst.parent.mkdir(parents=True, exist_ok=True)
tmp = dst.with_suffix(dst.suffix + ".tmp")
tmp.write_text("\n".join(lines) + "\n")
tmp.replace(dst)

print("generated:", dst)
print("artifact sha256:", fields["registry_artifact_sha256"])
PY
