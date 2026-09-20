#!/usr/bin/env bash
set -euo pipefail

release_input="${1:?release json required}"
evidence_input="${2:?evidence json required}"
semantics_input="${3:?semantics json required}"
output="${4:?output include required}"

python3 - "$release_input" "$evidence_input" "$semantics_input" "$output" <<'PY'
import json
from pathlib import Path
import sys

release_src = Path(sys.argv[1])
evidence_src = Path(sys.argv[2])
semantics_src = Path(sys.argv[3])
dst = Path(sys.argv[4])

data = json.loads(release_src.read_text())
evidence = json.loads(evidence_src.read_text())
semantics = json.loads(semantics_src.read_text())
r = data["release"]

artifact = next(a for a in r["artifacts"] if a["kind"] == "source")
stable = next(v for v in r["variants"] if v.get("stability") == "stable")
experimental = next(
    (v for v in r["variants"] if v.get("stability") == "experimental"),
    stable,
)

if evidence["artifact"]["sha256"] != artifact["sha256"]:
    raise SystemExit("evidence index Artifact does not match Release Artifact")
if semantics["project"] != data["project"] or semantics["release"] != r["version"]:
    raise SystemExit("semantic resource identity does not match Release")

required = stable["target"]["isa"]["required"]
review = r.get("review", {})
safety = r.get("safety", {})
advisories = safety.get("advisories", [])
perf = r.get("performance", {})

count = len(evidence.get("accepted_records", []))
ranking = (
    "comparable-evidence"
    if count
    else "stable fallback; no accepted comparable evidence"
)

matches = semantics["profile_matches"]
core_ref = semantics["declared_profile"]
strict_ref = "asmory/simd-dot-strict@1.0.0"
strict_rejections = matches[strict_ref]["rejections"]
strict_reason = strict_rejections[0]["path"] if strict_rejections else "none"

canon = semantics["canonical_semantics"]
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
    "registry_perf_benchmark": evidence["benchmark_contract"]["id"],
    "registry_perf_contract_sha256": evidence["benchmark_contract"]["sha256"],
    "registry_perf_evidence_status": evidence["status"],
    "registry_perf_evidence_count": str(count),
    "registry_perf_ranking": ranking,
    "registry_perf_endpoint": perf.get(
        "evidence_endpoint",
        "/api/v1/packages/simd-dot/0.1.0/evidence",
    ),
    "registry_semantic_fingerprint": semantics["semantic_fingerprint"],
    "registry_semantic_interface": canon["interface"]["shape"],
    "registry_semantic_alignment": str(
        canon["requires"]["memory"]["alignment_min_bytes"]
    ),
    "registry_semantic_abs_error": str(
        canon["guarantees"]["numeric"]["absolute_error_max"]
    ),
    "registry_semantic_rel_error": str(
        canon["guarantees"]["numeric"]["relative_error_max"]
    ),
    "registry_semantic_determinism": canon["guarantees"]["determinism"]["level"],
    "registry_semantic_core_profile": core_ref,
    "registry_semantic_strict_profile": strict_ref,
    "registry_semantic_core_result": (
        "compatible/exact"
        if matches[core_ref]["compatible"] and matches[core_ref]["exact_semantic_identity"]
        else "rejected"
    ),
    "registry_semantic_strict_result": (
        "compatible" if matches[strict_ref]["compatible"] else "rejected"
    ),
    "registry_semantic_strict_reason": strict_reason,
    "registry_semantic_endpoint": (
        "/api/v1/packages/simd-dot/0.1.0/semantics"
    ),
}

def gas_string(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
    )

lines = [
    "# Generated from exact Registry Release + Evidence + Semantic JSON.",
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
print("semantic fingerprint:", fields["registry_semantic_fingerprint"])
print("accepted evidence:", count)
PY
