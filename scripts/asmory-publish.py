#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib


class PublishError(RuntimeError):
    pass


def run(args: list[str], *, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            args,
            cwd=cwd,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise PublishError(f"command failed: {' '.join(args)}: {exc}") from exc


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def canonical_json(value: dict) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode("utf-8")


def workspace_root() -> Path:
    root = Path.cwd().resolve()
    if not (root / "asmory.workspace.toml").is_file():
        raise PublishError("no repository workspace; create/fork a Package first")
    return root


def package_manifest(root: Path, subdir: str) -> dict:
    path = root / subdir / "asmory.package.toml"
    try:
        data = tomllib.loads(path.read_text())
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise PublishError(f"cannot read package manifest: {exc}") from exc

    if data.get("schema") != 1 or not isinstance(data.get("package"), dict):
        raise PublishError("unsupported package manifest")

    return data


def prepare(root: Path, package: str) -> int:
    # Workspace helper validates self-contained boundaries and exact package
    # selection before we create any publication material.
    run(["asmory-workspace", "check"], cwd=root)

    try:
        meta = json.loads(
            run(["asmory-workspace", "metadata", package], cwd=root).stdout
        )
        source = json.loads(
            run(["asmory-workspace", "provenance", package], cwd=root).stdout
        )
    except json.JSONDecodeError as exc:
        raise PublishError(f"workspace helper returned invalid JSON: {exc}") from exc

    if source.get("worktree_dirty") is True:
        raise PublishError(
            f"{package}: Package root is dirty; commit the fork/package before publication prepare"
        )

    if source.get("worktree_dirty") is not False:
        raise PublishError("workspace provenance dirty state is invalid")

    manifest = package_manifest(root, meta["subdir"])
    origin = manifest.get("origin")

    if origin is not None and not isinstance(origin, dict):
        raise PublishError("package origin metadata is malformed")

    name = meta.get("name")
    version = meta.get("version")

    if not isinstance(name, str) or name != package:
        raise PublishError("workspace Package identity mismatch")

    if not isinstance(version, str) or not version:
        raise PublishError("workspace Package version missing")

    runtime = root / ".asmory" / ".publish"
    runtime.mkdir(mode=0o700, parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix=f"publish-{name}-", dir=runtime) as td:
        stage = Path(td)
        artifact_name = f"{name}-{version}.tar.gz"
        artifact = stage / artifact_name

        run(["asmory-workspace", "pack", name, str(artifact)], cwd=root)

        digest = sha256_file(artifact)
        size = artifact.stat().st_size

        listing = run(["tar", "-tzf", str(artifact)]).stdout.splitlines()
        if f"{name}/asmory.package.toml" in listing:
            raise PublishError("repository control manifest leaked into source Artifact")

        candidate = {
            "schema": 1,
            "kind": "asmory-release-candidate",
            "package": {
                "name": name,
                "version": version,
            },
            "source": source,
            "artifact": {
                "kind": "source",
                "filename": artifact_name,
                "sha256": digest,
                "size": size,
            },
            "boundary": {
                "self_contained": True,
                "package_manifest_in_artifact": False,
            },
            "origin": origin,
        }

        candidate_bytes = canonical_json(candidate)
        candidate_sha = hashlib.sha256(candidate_bytes).hexdigest()
        candidate_path = stage / "release-candidate.json"
        candidate_path.write_bytes(candidate_bytes)

        output = runtime / name / version

        if output.exists():
            existing_candidate = output / "release-candidate.json"
            existing_artifact = output / artifact_name

            if (
                existing_candidate.is_file()
                and existing_artifact.is_file()
                and existing_candidate.read_bytes() == candidate_bytes
                and sha256_file(existing_artifact) == digest
            ):
                print("Publication candidate already prepared")
                print()
                print(f"  package      {name}@{version}")
                print(f"  artifact     {digest}")
                print(f"  candidate    {candidate_sha}")
                print(f"  local        .asmory/.publish/{name}/{version}")
                print("  remote       not uploaded")
                return 0

            raise PublishError(
                f"publication candidate destination already exists with different bytes: "
                f".asmory/.publish/{name}/{version}"
            )

        output.parent.mkdir(parents=True, exist_ok=True)
        os.rename(stage, output)

    print("Publication candidate prepared")
    print()
    print(f"  package      {name}@{version}")
    print(f"  artifact     {digest}")
    print(f"  candidate    {candidate_sha}")
    print(f"  source       {source['repository']}@{source['commit']}")
    print(f"  subdir       {source['subdir']}")
    print(f"  local        .asmory/.publish/{name}/{version}")
    print("  remote       not uploaded")
    print("  next         authenticated Registry publish API")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="asmory-publish")
    parser.add_argument("package")
    args = parser.parse_args()

    try:
        root = workspace_root()
        return prepare(root, args.package)
    except (PublishError, OSError, tomllib.TOMLDecodeError) as exc:
        print(f"publish-prepare: {exc}", file=sys.stderr)
        return 23


if __name__ == "__main__":
    raise SystemExit(main())
