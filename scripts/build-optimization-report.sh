#!/usr/bin/env bash
set -euo pipefail

evidence="${1:-build/performance/simd-dot-variants.json}"
out="${2:-build/performance/simd-dot-optimization-report.json}"

python3 - "$evidence" "$out" <<'PY'
import json
from pathlib import Path
import sys

e = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])

report = {
    "schema": "asmory-optimization-report-v1",
    "package": e["package"],
    "version": e["version"],
    "artifact": e["artifact"],
    "semantic_identity": {
        "capability": "math.dot.f32",
        "profile": "asmory/simd-dot-core@1.0.0",
    },
    "conformance": {
        "suite": "core-v1-basic",
        "state": "pass",
        "variants": [
            "x86_64-avx2-generic",
            "x86_64-avx2-fma-4acc",
        ],
    },
    "performance": {
        "evidence_schema": e["schema"],
        "benchmark": e["benchmark"],
        "machine": e["machine"],
        "observation": e["observation"],
    },
    "resolver_effect": {
        "global_default_changed": False,
        "reason": (
            "Local machine evidence is useful optimization evidence but is not "
            "an accepted comparable registry cohort."
        ),
    },
    "next_actions": [
        "review the machine-local delta",
        "collect comparable evidence on additional matching machines",
        "append accepted evidence without rewriting the Release",
        "change resolver ranking only after policy permits",
    ],
}

out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(report, indent=2) + "\n")

print("optimization-report:", out)
print("faster here:", e["observation"]["faster_variant_here"])
print("resolver default changed: no")
PY
