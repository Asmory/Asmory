#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tomllib

WORKSPACE_FILE = "asmory.workspace.toml"
PACKAGE_FILE = "asmory.package.toml"
NAME_RE = re.compile(r"[a-z0-9][a-z0-9._-]*")
VERSION_RE = re.compile(r"[0-9]+(?:\.[0-9]+){2}(?:[-+][0-9A-Za-z.-]+)?")
GIT_SHA_RE = re.compile(r"[0-9a-f]{40}")
INCLUDE_PATTERNS = (
    re.compile(r'^\s*\.include\s+"([^"]+)"'),
    re.compile(r'^\s*%include\s+"([^"]+)"', re.IGNORECASE),
    re.compile(r'^\s*#\s*include\s+"([^"]+)"'),
)
ASM_SUFFIXES = {".S", ".s", ".asm", ".inc"}


class WorkspaceError(RuntimeError):
    pass


def find_workspace(start: Path) -> Path:
    current = start.resolve()
    while True:
        if (current / WORKSPACE_FILE).is_file():
            return current
        if current.parent == current:
            raise WorkspaceError(f"no {WORKSPACE_FILE} found from {start}")
        current = current.parent


def load_toml(path: Path) -> dict:
    try:
        return tomllib.loads(path.read_text())
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise WorkspaceError(f"cannot read {path}: {exc}") from exc


def normalized_member(text: str) -> PurePosixPath:
    path = PurePosixPath(text)
    if path.is_absolute() or not path.parts:
        raise WorkspaceError(f"workspace member must be relative: {text!r}")
    if any(part in ("", ".", "..") for part in path.parts):
        raise WorkspaceError(f"unsafe workspace member path: {text!r}")
    return path


def git(root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            ["git", "-C", str(root), *args],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise WorkspaceError(f"git {' '.join(args)} failed: {exc}") from exc


def load_workspace(root: Path) -> dict:
    data = load_toml(root / WORKSPACE_FILE)
    if data.get("schema") != 1:
        raise WorkspaceError("unsupported repository workspace schema")
    ws = data.get("workspace")
    if not isinstance(ws, dict):
        raise WorkspaceError("[workspace] table missing")
    repository = ws.get("repository")
    if not isinstance(repository, str) or not repository.strip():
        raise WorkspaceError("workspace.repository is required")
    members = ws.get("members")
    if not isinstance(members, list) or not members:
        raise WorkspaceError("workspace.members must be a non-empty array")

    normalized = [normalized_member(str(v)) for v in members]
    strings = [p.as_posix() for p in normalized]
    if strings != sorted(strings):
        raise WorkspaceError("workspace.members must be sorted for deterministic discovery")
    if len(strings) != len(set(strings)):
        raise WorkspaceError("workspace.members contains duplicates")

    for i, left in enumerate(normalized):
        for right in normalized[i + 1:]:
            lp, rp = left.parts, right.parts
            if lp == rp[:len(lp)] or rp == lp[:len(rp)]:
                raise WorkspaceError(
                    f"nested workspace members are not allowed: {left} / {right}"
                )
    return {"repository": repository, "members": normalized}


def ensure_inside(root: Path, path: Path, label: str) -> Path:
    rr = root.resolve()
    resolved = path.resolve()
    try:
        resolved.relative_to(rr)
    except ValueError as exc:
        raise WorkspaceError(f"{label} escapes workspace root: {path}") from exc
    return resolved


def scan_literal_includes(package_root: Path) -> None:
    rr = package_root.resolve()
    for path in sorted(package_root.rglob("*")):
        if not path.is_file() or path.suffix not in ASM_SUFFIXES:
            continue
        try:
            text = path.read_text(errors="strict")
        except UnicodeDecodeError:
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            include = None
            for pattern in INCLUDE_PATTERNS:
                m = pattern.match(line)
                if m:
                    include = m.group(1)
                    break
            if include is None:
                continue
            inc = PurePosixPath(include)
            if inc.is_absolute():
                raise WorkspaceError(
                    f"{path}:{lineno}: absolute include escapes package boundary: {include!r}"
                )
            candidate = (path.parent / include).resolve()
            try:
                candidate.relative_to(rr)
            except ValueError as exc:
                raise WorkspaceError(
                    f"{path}:{lineno}: include escapes package root: {include!r}"
                ) from exc
            if not candidate.is_file():
                raise WorkspaceError(
                    f"{path}:{lineno}: literal include not found inside package: {include!r}"
                )


def validate_package_tree(package_root: Path) -> None:
    if not package_root.is_dir() or package_root.is_symlink():
        raise WorkspaceError(f"package root is missing or symlinked: {package_root}")
    for path in sorted(package_root.rglob("*")):
        if path.is_symlink():
            raise WorkspaceError(
                f"source package v1 rejects symlinks: {path.relative_to(package_root)}"
            )
        if not (path.is_file() or path.is_dir()):
            raise WorkspaceError(
                f"source package v1 rejects special files: {path.relative_to(package_root)}"
            )
    scan_literal_includes(package_root)


def load_packages(root: Path, workspace: dict) -> list[dict]:
    packages = []
    names = set()
    for member in workspace["members"]:
        member_text = member.as_posix()
        package_root = ensure_inside(root, root / member_text, "package root")
        manifest = package_root / PACKAGE_FILE
        if not manifest.is_file():
            raise WorkspaceError(f"workspace member lacks {PACKAGE_FILE}: {member_text}")
        data = load_toml(manifest)
        if data.get("schema") != 1:
            raise WorkspaceError(f"{member_text}: unsupported package schema")
        pkg = data.get("package")
        if not isinstance(pkg, dict):
            raise WorkspaceError(f"{member_text}: [package] table missing")
        name = pkg.get("name")
        version = pkg.get("version")
        if not isinstance(name, str) or NAME_RE.fullmatch(name) is None:
            raise WorkspaceError(f"{member_text}: invalid package name {name!r}")
        if not isinstance(version, str) or VERSION_RE.fullmatch(version) is None:
            raise WorkspaceError(f"{member_text}: invalid package version {version!r}")
        if name in names:
            raise WorkspaceError(f"duplicate package name in repository workspace: {name}")
        if package_root.name != name:
            raise WorkspaceError(
                f"{member_text}: package directory basename must equal package name {name!r}"
            )
        validate_package_tree(package_root)
        names.add(name)
        packages.append(
            {"name": name, "version": version, "path": member_text, "root": package_root}
        )
    return packages


def model(start: Path):
    root = find_workspace(start)
    workspace = load_workspace(root)
    return root, workspace, load_packages(root, workspace)


def find_package(packages: list[dict], name: str) -> dict:
    found = [p for p in packages if p["name"] == name]
    if len(found) != 1:
        raise WorkspaceError(f"package is not a unique workspace member: {name}")
    return found[0]


def provenance(root: Path, workspace: dict, package: dict) -> dict:
    if git(root, "rev-parse", "--is-inside-work-tree").stdout.strip() != "true":
        raise WorkspaceError("repository workspace is not inside Git")
    commit = git(root, "rev-parse", "HEAD").stdout.strip()
    if GIT_SHA_RE.fullmatch(commit) is None:
        raise WorkspaceError("Git HEAD is not a full 40-hex commit")
    status = git(
        root,
        "status",
        "--porcelain",
        "--untracked-files=all",
        "--",
        package["path"],
    ).stdout
    return {
        "kind": "git",
        "repository": workspace["repository"],
        "commit": commit,
        "subdir": package["path"],
        "worktree_dirty": bool(status.strip()),
    }


def pack(package: dict, output: Path) -> None:
    output = output.absolute()
    output.parent.mkdir(parents=True, exist_ok=True)

    # asmory.package.toml defines repository development topology. It is
    # control metadata, not source Artifact v1 payload. This allows workspace
    # metadata to evolve without rewriting immutable existing Releases.
    excluded = f"{package['root'].name}/{PACKAGE_FILE}"

    try:
        subprocess.run(
            [
                "tar",
                "--sort=name",
                "--mtime=UTC 1970-01-01",
                "--owner=0",
                "--group=0",
                "--numeric-owner",
                f"--exclude={excluded}",
                "-czf",
                str(output),
                "-C",
                str(package["root"].parent),
                package["root"].name,
            ],
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise WorkspaceError(f"deterministic tar creation failed: {exc}") from exc

def print_list(root: Path, workspace: dict, packages: list[dict]) -> None:
    print("Asmory repository workspace")
    print()
    print(f"  root        {root}")
    print(f"  repository  {workspace['repository']}")
    print(f"  packages    {len(packages)}")
    for pkg in packages:
        print()
        print(f"{pkg['name']} {pkg['version']}")
        print(f"  path        {pkg['path']}")
        print("  boundary    self-contained")


def main() -> int:
    parser = argparse.ArgumentParser(prog="asmory-workspace")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("list")
    sub.add_parser("check")
    p = sub.add_parser("path"); p.add_argument("package")
    p = sub.add_parser("metadata"); p.add_argument("package")
    p = sub.add_parser("provenance"); p.add_argument("package")
    p = sub.add_parser("publish-check"); p.add_argument("package")
    p = sub.add_parser("pack"); p.add_argument("package"); p.add_argument("output")
    args = parser.parse_args()
    command = args.command or "list"

    try:
        root, workspace, packages = model(Path.cwd())
        if command == "list":
            print_list(root, workspace, packages)
            return 0
        if command == "check":
            suffix = "s" if len(packages) != 1 else ""
            print(f"repository-workspace: ok ({len(packages)} package{suffix})")
            return 0

        pkg = find_package(packages, args.package)
        if command == "path":
            print(pkg["path"]); return 0
        if command == "metadata":
            print(json.dumps({
                "name": pkg["name"], "version": pkg["version"],
                "subdir": pkg["path"], "repository": workspace["repository"],
            }, sort_keys=True, separators=(",", ":")))
            return 0
        if command == "provenance":
            print(json.dumps(
                provenance(root, workspace, pkg),
                sort_keys=True, separators=(",", ":")
            ))
            return 0
        if command == "publish-check":
            src = provenance(root, workspace, pkg)
            if src["worktree_dirty"]:
                raise WorkspaceError(
                    f"{pkg['name']}: package root is dirty; publish provenance requires committed source"
                )
            print(f"publish-provenance: ok {pkg['name']} {src['commit']} {src['subdir']}")
            return 0
        if command == "pack":
            pack(pkg, Path(args.output))
            print(Path(args.output))
            return 0
        raise WorkspaceError(f"unsupported command: {command}")
    except WorkspaceError as exc:
        print(f"workspace: {exc}", file=sys.stderr)
        return 21


if __name__ == "__main__":
    raise SystemExit(main())
