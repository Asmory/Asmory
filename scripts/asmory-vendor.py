#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fcntl
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import tomllib


class VendorError(RuntimeError):
    pass


def workspace_root() -> Path:
    root = Path.cwd()

    if not (root / "asm.toml").is_file() or not (root / "asm.lock").is_file():
        raise VendorError("no initialized Asmory workspace; run 'asmory init' first")

    if not (root / ".asmory" / "deps").is_dir():
        raise VendorError("workspace dependency root is missing")

    return root


def load_lock(root: Path) -> tuple[dict, dict]:
    try:
        data = tomllib.loads((root / "asm.lock").read_text())
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise VendorError(f"cannot read asm.lock: {exc}") from exc

    if data.get("schema") != 1 or data.get("resolver_policy") != "asmory-v1":
        raise VendorError("unsupported asm.lock format")

    deps = data.get("dependency", [])
    if not isinstance(deps, list) or data.get("dependency_count") != len(deps):
        raise VendorError("asm.lock dependency records are malformed")

    return data, {dep.get("name"): dep for dep in deps if isinstance(dep, dict)}


def load_manifest(root: Path) -> dict:
    try:
        return tomllib.loads((root / "asm.toml").read_text())
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise VendorError(f"cannot read asm.toml: {exc}") from exc


def tree_hash(path: Path) -> str:
    try:
        proc = subprocess.run(
            ["asmory-state", "tree-hash", str(path)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise VendorError(f"cannot compute tree hash for {path}: {exc}") from exc

    value = proc.stdout.strip()

    if re.fullmatch(r"[0-9a-f]{64}", value) is None:
        raise VendorError("state helper returned an invalid tree hash")

    return value


def copy_owned_tree(source: Path, destination: Path) -> None:
    if not source.is_dir() or source.is_symlink():
        raise VendorError(f"source tree is missing or invalid: {source}")

    destination.mkdir(mode=stat.S_IMODE(source.lstat().st_mode) & 0o777)

    def walk(src: Path, dst: Path) -> None:
        for entry in sorted(os.scandir(src), key=lambda e: os.fsencode(e.name)):
            src_path = Path(entry.path)
            dst_path = dst / entry.name
            st = entry.stat(follow_symlinks=False)
            mode = stat.S_IMODE(st.st_mode)

            if mode & ~0o777:
                raise VendorError(
                    f"vendor MVP rejects special permission bits: {src_path}"
                )

            if stat.S_ISDIR(st.st_mode):
                dst_path.mkdir(mode=mode)
                walk(src_path, dst_path)
                dst_path.chmod(mode)
                continue

            if stat.S_ISREG(st.st_mode):
                shutil.copyfile(src_path, dst_path, follow_symlinks=False)
                dst_path.chmod(mode)
                continue

            if stat.S_ISLNK(st.st_mode):
                os.symlink(os.readlink(src_path), dst_path)
                continue

            raise VendorError(f"vendor MVP rejects special file: {src_path}")

    walk(source, destination)


def remove_path(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    elif path.exists() or path.is_symlink():
        path.unlink()


def rewrite_manifest(text: str, package: str, vendor_path: str) -> str:
    pattern = re.compile(
        rf"(?m)^{re.escape(package)}\s*=\s*\"\*\"\s*$"
    )
    replacement = f'{package} = {{ path = "{vendor_path}" }}'
    result, count = pattern.subn(replacement, text, count=1)

    if count != 1:
        raise VendorError(
            f"{package}: expected canonical registry dependency intent in asm.toml"
        )

    return result


def rewrite_lock(
    text: str,
    package: str,
    vendor_path: str,
    origin_tree: str,
) -> str:
    try:
        parsed = tomllib.loads(text)
    except tomllib.TOMLDecodeError as exc:
        raise VendorError(f"cannot parse asm.lock before vendor transition: {exc}") from exc

    deps = parsed.get("dependency", [])
    matches = [dep for dep in deps if dep.get("name") == package]

    if len(matches) != 1:
        raise VendorError(f"{package}: expected exactly one lockfile dependency record")

    dep = matches[0]
    source_kind = dep.get("source_kind", "registry")

    if source_kind != "registry":
        raise VendorError(f"{package}: dependency is already {source_kind!r}")

    if dep.get("materialized_path") != f".asmory/deps/{package}":
        raise VendorError(f"{package}: registry materialization path is non-canonical")

    if "vendor_path" in dep or "vendor_origin_tree_sha256" in dep:
        raise VendorError(f"{package}: stale vendor metadata already exists")

    marker = f'materialized_path = ".asmory/deps/{package}"'
    if text.count(marker) != 1:
        raise VendorError(f"{package}: cannot locate canonical lockfile path field")

    source_marker = 'source_kind = "registry"'

    if text.count(source_marker) == 1:
        text = text.replace(source_marker, 'source_kind = "vendor"', 1)
        insertion = (
            marker
            + f'\nvendor_path = "{vendor_path}"'
            + f'\nvendor_origin_tree_sha256 = "{origin_tree}"'
        )
    elif text.count(source_marker) == 0:
        insertion = (
            marker
            + '\nsource_kind = "vendor"'
            + f'\nvendor_path = "{vendor_path}"'
            + f'\nvendor_origin_tree_sha256 = "{origin_tree}"'
        )
    else:
        raise VendorError(f"{package}: ambiguous registry source metadata")

    return text.replace(marker, insertion, 1)


def vendor_dependency(root: Path, package: str) -> int:
    if re.fullmatch(r"[a-z0-9][a-z0-9._-]*", package) is None:
        raise VendorError("invalid package name")

    data, by_name = load_lock(root)
    dep = by_name.get(package)

    if dep is None:
        raise VendorError(f"dependency not found in asm.lock: {package}")

    source_kind = dep.get("source_kind", "registry")
    if source_kind != "registry":
        raise VendorError(f"{package}: dependency source is already {source_kind}")

    materialized = root / f".asmory/deps/{package}"
    vendor_rel = f"vendor/{package}"
    vendor_path = root / vendor_rel

    if not materialized.is_dir() or materialized.is_symlink():
        raise VendorError(
            f"{package}: local registry materialization is missing or invalid"
        )

    if vendor_path.exists() or vendor_path.is_symlink():
        raise VendorError(f"{package}: vendor destination already exists: {vendor_rel}")

    manifest = load_manifest(root)
    deps = manifest.get("dependencies", {})
    if not isinstance(deps, dict) or deps.get(package) != "*":
        raise VendorError(
            f"{package}: manifest intent is not the canonical registry dependency"
        )

    lock_path = root / ".asmory" / "workspace.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)

    with lock_path.open("a+b") as lock_file:
        try:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise VendorError("another Asmory workspace mutation is in progress") from exc

        # Re-check the user-visible source after acquiring the workspace lock.
        if not materialized.is_dir() or materialized.is_symlink():
            raise VendorError(f"{package}: source materialization changed during transition")

        source_before = tree_hash(materialized)

        runtime = root / ".asmory" / ".vendor"
        runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
        stage = Path(tempfile.mkdtemp(prefix=f"vendor-{package}-", dir=runtime))
        candidate = stage / package
        source_backup = runtime / f"source-backup-{package}-{os.getpid()}"

        tmp_manifest = stage / "asm.toml"
        tmp_lock = stage / "asm.lock"
        manifest_backup = stage / "asm.toml.backup"
        lock_backup = stage / "asm.lock.backup"

        vendor_published = False
        source_moved = False
        metadata_started = False
        committed = False

        try:
            copy_owned_tree(materialized, candidate)

            source_after = tree_hash(materialized)
            candidate_hash = tree_hash(candidate)

            if source_before != source_after or candidate_hash != source_after:
                raise VendorError(
                    f"{package}: source changed while vendor snapshot was being captured"
                )

            manifest_text = (root / "asm.toml").read_text()
            lock_text = (root / "asm.lock").read_text()

            tmp_manifest.write_text(
                rewrite_manifest(manifest_text, package, vendor_rel)
            )
            tmp_lock.write_text(
                rewrite_lock(lock_text, package, vendor_rel, candidate_hash)
            )

            # Validate both new metadata files before publishing any state.
            tomllib.loads(tmp_manifest.read_text())
            new_lock = tomllib.loads(tmp_lock.read_text())
            new_dep = [
                item for item in new_lock.get("dependency", [])
                if item.get("name") == package
            ][0]

            if (
                new_dep.get("source_kind") != "vendor"
                or new_dep.get("vendor_path") != vendor_rel
                or new_dep.get("vendor_origin_tree_sha256") != candidate_hash
            ):
                raise VendorError("generated vendor lock metadata failed validation")

            vendor_path.parent.mkdir(parents=True, exist_ok=True)

            if source_backup.exists() or source_backup.is_symlink():
                remove_path(source_backup)

            os.rename(materialized, source_backup)
            source_moved = True

            os.rename(candidate, vendor_path)
            vendor_published = True

            shutil.copyfile(root / "asm.toml", manifest_backup)
            shutil.copyfile(root / "asm.lock", lock_backup)

            metadata_started = True
            os.replace(tmp_manifest, root / "asm.toml")
            os.replace(tmp_lock, root / "asm.lock")

            if tree_hash(vendor_path) != candidate_hash:
                raise VendorError("post-publication vendor tree verification failed")

            # Re-read published metadata as the last commit check.
            published_manifest = tomllib.loads((root / "asm.toml").read_text())
            published_lock = tomllib.loads((root / "asm.lock").read_text())

            if published_manifest.get("dependencies", {}).get(package) != {
                "path": vendor_rel
            }:
                raise VendorError("published manifest vendor intent verification failed")

            published_dep = [
                item for item in published_lock.get("dependency", [])
                if item.get("name") == package
            ][0]
            if published_dep.get("source_kind") != "vendor":
                raise VendorError("published lock vendor source verification failed")

            committed = True

            if source_backup.exists() or source_backup.is_symlink():
                remove_path(source_backup)

        finally:
            if not committed:
                if metadata_started:
                    if manifest_backup.exists():
                        shutil.copyfile(manifest_backup, root / "asm.toml")
                    if lock_backup.exists():
                        shutil.copyfile(lock_backup, root / "asm.lock")

                if vendor_published:
                    remove_path(vendor_path)

                if source_moved and (source_backup.exists() or source_backup.is_symlink()):
                    if materialized.exists() or materialized.is_symlink():
                        remove_path(materialized)
                    os.rename(source_backup, materialized)

            shutil.rmtree(stage, ignore_errors=True)

    print("Dependency vendored")
    print()
    print(f"  package      {package}")
    print("  ownership    project")
    print(f"  source       {vendor_rel}")
    print(f"  tree         {source_after}")
    print(f"  base         {dep.get('artifact_sha256', '?')}")
    print("  registry     provenance retained in asm.lock")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="asmory-vendor")
    parser.add_argument("package")
    args = parser.parse_args()

    try:
        root = workspace_root()
        return vendor_dependency(root, args.package)
    except (VendorError, OSError, tomllib.TOMLDecodeError) as exc:
        print(f"vendor: {exc}", file=sys.stderr)
        return 20


if __name__ == "__main__":
    raise SystemExit(main())
