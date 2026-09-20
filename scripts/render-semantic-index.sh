#!/usr/bin/env bash
set -euo pipefail

implementation="${1:?implementation semantics required}"
core="${2:?core profile required}"
strict="${3:?strict profile required}"
suite="${4:?conformance suite required}"
outdir="${5:?output directory required}"

python3 - "$implementation" "$core" "$strict" "$suite" "$outdir" <<'PY'
import json
from pathlib import Path
import sys
import tomllib

sys.path.insert(0, str(Path("scripts").resolve()))
from semantic_model import canonical_semantics, fingerprint, match

impl_path, core_path, strict_path, suite_path, outdir = map(Path, sys.argv[1:])
outdir.mkdir(parents=True, exist_ok=True)

impl = tomllib.loads(impl_path.read_text())
core = tomllib.loads(core_path.read_text())
strict = tomllib.loads(strict_path.read_text())
suite = tomllib.loads(suite_path.read_text())

core_ref = f'{core["profile"]["id"]}@{core["profile"]["version"]}'
strict_ref = f'{strict["profile"]["id"]}@{strict["profile"]["version"]}'

if impl["profile"] != core_ref:
    raise SystemExit("implementation claims a different Profile than core-v1")

impl_fp = fingerprint(impl)
core_fp = fingerprint(core)
strict_fp = fingerprint(strict)

if impl_fp != core_fp:
    raise SystemExit(
        "implementation and claimed core Profile do not have exact semantic identity"
    )

core_match = match(core, impl)
strict_match = match(strict, impl)

if not core_match["compatible"] or not core_match["exact_semantic_identity"]:
    raise SystemExit("core Profile must be an exact semantic match")
if strict_match["compatible"]:
    raise SystemExit("strict Profile should be a semantic alternative for this MVP")

covered = {x["path"] for x in suite["suite"]["facets"]}
required_coverage = {
    "interface.shape",
    "requires.memory.alignment_min_bytes",
    "guarantees.memory.inputs_written",
    "guarantees.memory.out_of_bounds_access",
    "guarantees.numeric.absolute_error_max",
    "guarantees.numeric.relative_error_max",
    "guarantees.determinism.level",
}
missing = sorted(required_coverage - covered)
if missing:
    raise SystemExit("conformance suite missing facet coverage: " + ", ".join(missing))

capability = {
    "registry": "Asmory",
    "schema": 1,
    "capability": {
        "id": impl["capability"],
        "authority": "none",
        "purpose": "discovery-index",
        "profiles": [core_ref, strict_ref],
        "implementations": [
            {
                "project": "simd-dot",
                "release": "0.1.0",
                "provider": "Asmory/Asmory",
                "semantic_fingerprint": impl_fp,
            }
        ],
    },
}

core_resource = {
    "registry": "Asmory",
    "schema": 1,
    "profile": core["profile"],
    "semantic_fingerprint": core_fp,
    "canonical_semantics": canonical_semantics(core),
    "conformance_suite": suite["suite"]["id"],
}

strict_resource = {
    "registry": "Asmory",
    "schema": 1,
    "profile": strict["profile"],
    "semantic_fingerprint": strict_fp,
    "canonical_semantics": canonical_semantics(strict),
}

semantics = {
    "registry": "Asmory",
    "schema": 1,
    "project": "simd-dot",
    "release": "0.1.0",
    "provider": "Asmory/Asmory",
    "capability": impl["capability"],
    "declared_profile": core_ref,
    "semantic_fingerprint": impl_fp,
    "canonical_semantics": canonical_semantics(impl),
    "profile_matches": {
        core_ref: core_match,
        strict_ref: strict_match,
    },
    "conformance": {
        "suite": suite["suite"]["id"],
        "runner": suite["suite"]["runner"],
        "facet_coverage": sorted(covered),
    },
    "principles": {
        "profile_name_is_authority": False,
        "provider_is_semantic_identity": False,
        "capability_is_semantic_authority": False,
        "facets_are_source_of_truth": True,
    },
}

files = {
    "simd-dot-semantics.json": semantics,
    "capability-math-dot-f32.json": capability,
    "profile-simd-dot-core-v1.json": core_resource,
    "profile-simd-dot-strict-v1.json": strict_resource,
}

for name, data in files.items():
    p = outdir / name
    p.write_text(json.dumps(data, separators=(",", ":")) + "\n")
    print("semantic-resource:", p)

print("implementation fingerprint:", impl_fp)
print("core fingerprint:          ", core_fp)
print("strict fingerprint:        ", strict_fp)
print("core match:                compatible / exact")
print("strict match:              rejected")
for r in strict_match["rejections"]:
    print("  reject:", r["path"], "-", r["explanation"])
PY
