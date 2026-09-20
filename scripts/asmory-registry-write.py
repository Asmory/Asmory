#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import fcntl
import hashlib
import hmac
import json
import os
from pathlib import Path, PurePosixPath
import re
import socket
import stat
import sys
import tarfile
import tempfile
import tomllib
from urllib.parse import parse_qs, urlsplit

NAME_RE = re.compile(r"[a-z0-9][a-z0-9._-]*")
VERSION_RE = re.compile(r"[0-9]+(?:\.[0-9]+){2}(?:[-+][0-9A-Za-z.-]+)?")
SHA_RE = re.compile(r"[0-9a-f]{64}")
OWNER_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
ID_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._+@/-]{0,255}")
MAX_CANDIDATE = 1024 * 1024
MAX_PROMOTION_REQUEST = 64 * 1024
MAX_METADATA_FILE = 1024 * 1024
MAX_ARCHIVE_MEMBERS = 10_000
DEFAULT_MAX_ARTIFACT = 8 * 1024 * 1024 * 1024
DEFAULT_MAX_UNPACKED = 512 * 1024 * 1024


class RegistryError(RuntimeError):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def canonical_json(value: dict) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode("utf-8")


def _normalize(value):
    if isinstance(value, dict):
        return {k: _normalize(value[k]) for k in sorted(value)}
    if isinstance(value, list):
        if all(isinstance(x, str) for x in value):
            return sorted(set(value))
        return [_normalize(x) for x in value]
    return value


def canonical_semantics(doc: dict) -> dict:
    if "semantics" in doc:
        sem = dict(doc["semantics"])
        capability = doc.get("profile", {}).get("capability")
    else:
        sem = {
            "interface": dict(doc["interface"]),
            "requires": dict(doc.get("requires", {})),
            "guarantees": dict(doc.get("guarantees", {})),
        }
        capability = doc["capability"]

    return _normalize(
        {
            "schema": 1,
            "capability": capability,
            "interface": sem.get("interface", {}),
            "requires": sem.get("requires", {}),
            "guarantees": sem.get("guarantees", {}),
        }
    )


def semantic_fingerprint(doc: dict) -> str:
    body = json.dumps(
        canonical_semantics(doc),
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")
    return hashlib.sha256(body).hexdigest()


def fsync_dir(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def atomic_write(path: Path, data: bytes, mode: int = 0o444) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    tmp = Path(tmp_name)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "wb", closefd=True) as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
        fsync_dir(path.parent)
    finally:
        tmp.unlink(missing_ok=True)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def safe_relpath(text: str, label: str) -> PurePosixPath:
    if not isinstance(text, str) or not text:
        raise RegistryError(422, f"{label} path is missing")

    if "\\" in text:
        raise RegistryError(422, f"{label} path must use POSIX separators")

    path = PurePosixPath(text)
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise RegistryError(422, f"{label} path is unsafe: {text!r}")
    return path


class RegistryState:
    def __init__(
        self,
        data_dir: Path,
        auth_file: Path,
        max_artifact: int,
        max_unpacked: int,
    ):
        self.data_dir = data_dir
        self.auth_file = auth_file
        self.max_artifact = max_artifact
        self.max_unpacked = max_unpacked

        self.objects = data_dir / "objects" / "sha256"
        self.projects = data_dir / "projects"
        self.active_root = data_dir / "active"
        self.active = self.active_root / "projects"
        self.active_index_path = self.active_root / "index.json"
        self.locks = data_dir / "locks"
        self.incoming = data_dir / "incoming"

        for path in (
            self.objects,
            self.projects,
            self.active_root,
            self.active,
            self.locks,
            self.incoming,
        ):
            path.mkdir(parents=True, exist_ok=True)

        # The active index is derived entirely from immutable active Release
        # records. Rebuild on startup so restart/crash recovery cannot leave
        # a stale resolver/search view.
        self.rebuild_active_index()

    def auth_owner(self, header: str | None) -> str:
        if not header or not header.startswith("Bearer "):
            raise RegistryError(401, "missing Bearer publication token")

        token = header[7:].strip()
        if not (32 <= len(token) <= 512) or any(c.isspace() for c in token):
            raise RegistryError(401, "invalid publication token")

        try:
            st = self.auth_file.lstat()
        except OSError as exc:
            raise RegistryError(503, f"auth database unavailable: {exc}") from exc

        if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode):
            raise RegistryError(503, "auth database must be a regular non-symlink file")

        if stat.S_IMODE(st.st_mode) & 0o077:
            raise RegistryError(503, "auth database permissions are too broad")

        try:
            data = json.loads(self.auth_file.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            raise RegistryError(503, f"auth database invalid: {exc}") from exc

        if data.get("schema") != 1 or not isinstance(data.get("tokens"), list):
            raise RegistryError(503, "unsupported auth database")

        digest = hashlib.sha256(token.encode()).hexdigest()
        owner = None
        for record in data["tokens"]:
            stored = record.get("sha256")
            if not isinstance(stored, str):
                continue
            if hmac.compare_digest(stored, digest) and record.get("enabled") is True:
                candidate = record.get("owner")
                if isinstance(candidate, str) and OWNER_RE.fullmatch(candidate):
                    owner = candidate
                break

        if owner is None:
            raise RegistryError(401, "publication token is not authorized")

        return owner

    def project_lock(self, package: str):
        path = self.locks / f"{package}.lock"
        file = path.open("a+b")
        fcntl.flock(file.fileno(), fcntl.LOCK_EX)
        return file

    def active_index_lock(self):
        path = self.locks / "_active-index.lock"
        file = path.open("a+b")
        fcntl.flock(file.fileno(), fcntl.LOCK_EX)
        return file

    def object_path(self, digest: str) -> Path:
        return self.objects / digest

    def owner_path(self, package: str) -> Path:
        return self.projects / package / "owner.json"

    def candidate_path(self, package: str, version: str) -> Path:
        return self.projects / package / "candidates" / f"{version}.json"

    def active_release_path(self, package: str, version: str) -> Path:
        return self.active / package / "releases" / f"{version}.json"

    def active_versions(self, package: str) -> list[str]:
        releases = self.active / package / "releases"
        if not releases.is_dir():
            return []
        versions = []
        for path in releases.iterdir():
            if path.is_file() and path.suffix == ".json":
                version = path.stem
                if VERSION_RE.fullmatch(version):
                    versions.append(version)
        return sorted(versions)

    def load_active_release(self, package: str, version: str) -> dict:
        path = self.active_release_path(package, version)
        if not path.is_file() or path.is_symlink():
            raise RegistryError(404, "active Release not found")
        try:
            record = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            raise RegistryError(
                500,
                f"active Release record invalid: {exc}",
            ) from exc

        if (
            record.get("project") != package
            or record.get("resolvable") is not True
            or not isinstance(record.get("release"), dict)
            or record["release"].get("version") != version
            or record["release"].get("state") != "active"
        ):
            raise RegistryError(500, "active Release record identity is invalid")

        return record

    @staticmethod
    def version_key(version: str):
        m = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(.*)", version)
        if m is None:
            return (0, 0, 0, 0, version)
        suffix = m.group(4)
        return (
            int(m.group(1)),
            int(m.group(2)),
            int(m.group(3)),
            1 if suffix == "" else 0,
            suffix,
        )

    def active_versions_sorted(self, package: str) -> list[str]:
        return sorted(
            self.active_versions(package),
            key=self.version_key,
            reverse=True,
        )

    def active_version_summaries(self, package: str) -> list[dict]:
        result = []
        for version in self.active_versions_sorted(package):
            record = self.load_active_release(package, version)
            release = record["release"]
            variants = release.get("variants", [])
            artifacts = release.get("artifacts", [])
            artifact = artifacts[0] if artifacts else {}

            variant_count = len(variants) if isinstance(variants, list) else 0
            result.append(
                {
                    "version": version,
                    "published_at": release.get("published_at"),
                    "yanked": False,
                    "yank_reason": None,
                    "downloads": 0,
                    "variants": variant_count,
                    "endpoint": f"/api/v1/packages/{package}/{version}",
                    "state": release.get("state", "active"),
                    "artifact_sha256": artifact.get("sha256"),
                    "semantic_fingerprint": release.get("semantic_fingerprint"),
                    "capability": release.get("capability"),
                    "profile": release.get("profile"),
                }
            )
        return result

    def active_project_summary(self, package: str) -> dict:
        versions = self.active_versions_sorted(package)
        if not versions:
            raise RegistryError(404, "active Package not found")

        latest = self.load_active_release(package, versions[0])
        release = latest["release"]
        variants = release.get("variants", [])
        first_variant = variants[0] if isinstance(variants, list) and variants else {}
        target = first_variant.get("target", {}) if isinstance(first_variant, dict) else {}
        isa = target.get("isa", {}) if isinstance(target, dict) else {}

        return {
            "name": package,
            "owner": latest.get("owner"),
            "latest_version": versions[0],
            "release_count": len(versions),
            "capability": release.get("capability"),
            "profile": release.get("profile"),
            "semantic_fingerprint": release.get("semantic_fingerprint"),
            "arch": target.get("arch"),
            "abi": target.get("abi"),
            "baseline": isa.get("baseline"),
            "review": release.get("review", {}).get("state"),
            "safety": release.get("safety", {}).get("state"),
        }

    def build_active_index_document(self) -> dict:
        packages = []
        for entry in sorted(self.active.iterdir(), key=lambda p: p.name):
            if not entry.is_dir() or entry.is_symlink():
                continue
            package = entry.name
            if NAME_RE.fullmatch(package) is None:
                continue
            try:
                packages.append(self.active_project_summary(package))
            except RegistryError as exc:
                if exc.status == 404:
                    continue
                raise

        return {
            "registry": "Asmory",
            "schema": 1,
            "kind": "asmory-active-index",
            "packages": packages,
        }

    def rebuild_active_index(self) -> dict:
        with self.active_index_lock():
            document = self.build_active_index_document()
            atomic_write(
                self.active_index_path,
                canonical_json(document),
                0o444,
            )
            return document

    def load_active_index(self) -> dict:
        if not self.active_index_path.is_file() or self.active_index_path.is_symlink():
            return self.rebuild_active_index()

        try:
            data = json.loads(self.active_index_path.read_text())
        except (OSError, json.JSONDecodeError):
            return self.rebuild_active_index()

        if (
            data.get("registry") != "Asmory"
            or data.get("schema") != 1
            or data.get("kind") != "asmory-active-index"
            or not isinstance(data.get("packages"), list)
        ):
            return self.rebuild_active_index()

        return data

    def search_active_packages(
        self,
        query: str | None,
        capability: str | None,
        arch: str | None,
        limit: int,
    ) -> list[dict]:
        q = (query or "").casefold()
        index = self.load_active_index()
        results = []

        for summary in index["packages"]:
            if not isinstance(summary, dict):
                continue

            if capability and summary.get("capability") != capability:
                continue
            if arch and summary.get("arch") != arch:
                continue

            if q:
                haystack = " ".join(
                    str(summary.get(key) or "")
                    for key in (
                        "name",
                        "owner",
                        "capability",
                        "profile",
                        "arch",
                        "abi",
                        "baseline",
                    )
                ).casefold()
                if q not in haystack:
                    continue

            results.append(summary)
            if len(results) >= limit:
                break

        return results

    def validate_candidate(self, raw: bytes) -> dict:
        if len(raw) > MAX_CANDIDATE:
            raise RegistryError(413, "candidate exceeds 1 MiB")

        try:
            obj = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise RegistryError(400, f"candidate JSON invalid: {exc}") from exc

        if not isinstance(obj, dict):
            raise RegistryError(400, "candidate must be a JSON object")

        if canonical_json(obj) != raw:
            raise RegistryError(400, "candidate JSON must use canonical Asmory encoding")

        if obj.get("schema") != 1 or obj.get("kind") != "asmory-release-candidate":
            raise RegistryError(400, "unsupported release candidate")

        package = obj.get("package")
        source = obj.get("source")
        artifact = obj.get("artifact")
        boundary = obj.get("boundary")

        if not isinstance(package, dict):
            raise RegistryError(400, "candidate package identity missing")

        name = package.get("name")
        version = package.get("version")
        if not isinstance(name, str) or NAME_RE.fullmatch(name) is None:
            raise RegistryError(400, "candidate package name invalid")
        if not isinstance(version, str) or VERSION_RE.fullmatch(version) is None:
            raise RegistryError(400, "candidate package version invalid")

        if not isinstance(source, dict):
            raise RegistryError(400, "candidate source provenance missing")
        if source.get("kind") != "git":
            raise RegistryError(400, "candidate source provenance must be git")
        if source.get("worktree_dirty") is not False:
            raise RegistryError(400, "dirty source provenance cannot be staged")
        if not isinstance(source.get("repository"), str) or not source["repository"]:
            raise RegistryError(400, "candidate repository provenance missing")
        commit = source.get("commit")
        if not isinstance(commit, str) or re.fullmatch(r"[0-9a-f]{40}", commit) is None:
            raise RegistryError(400, "candidate Git commit invalid")
        subdir = source.get("subdir")
        safe_relpath(subdir, "candidate Git subdir")

        if not isinstance(artifact, dict):
            raise RegistryError(400, "candidate Artifact missing")
        digest = artifact.get("sha256")
        size = artifact.get("size")
        filename = artifact.get("filename")
        if artifact.get("kind") != "source":
            raise RegistryError(400, "candidate Artifact kind must be source")
        if not isinstance(digest, str) or SHA_RE.fullmatch(digest) is None:
            raise RegistryError(400, "candidate Artifact digest invalid")
        if not isinstance(size, int) or size < 0 or size > self.max_artifact:
            raise RegistryError(400, "candidate Artifact size invalid")
        if filename != f"{name}-{version}.tar.gz":
            raise RegistryError(400, "candidate Artifact filename does not match Package identity")

        if boundary != {
            "self_contained": True,
            "package_manifest_in_artifact": False,
        }:
            raise RegistryError(400, "candidate Package boundary declaration invalid")

        origin = obj.get("origin")
        if origin is not None:
            if not isinstance(origin, dict):
                raise RegistryError(400, "candidate origin must be null or object")
            for key in (
                "artifact_sha256",
                "base_tree_sha256",
                "source_tree_sha256",
                "semantic_fingerprint",
            ):
                value = origin.get(key)
                if value is not None and (
                    not isinstance(value, str) or SHA_RE.fullmatch(value) is None
                ):
                    raise RegistryError(400, f"candidate origin {key} invalid")

        return obj

    def verify_object(self, digest: str, size: int | None = None) -> Path:
        path = self.object_path(digest)
        if not path.is_file() or path.is_symlink():
            raise RegistryError(409, "candidate references Artifact that has not been uploaded")
        if size is not None and path.stat().st_size != size:
            raise RegistryError(500, "stored Artifact size mismatch")
        if sha256_file(path) != digest:
            raise RegistryError(500, "stored Artifact digest mismatch")
        return path

    def read_owner(self, package: str) -> str | None:
        path = self.owner_path(package)
        if not path.exists():
            return None
        try:
            data = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            raise RegistryError(500, f"project ownership record invalid: {exc}") from exc
        owner = data.get("owner")
        if (
            data.get("schema") != 1
            or data.get("package") != package
            or not isinstance(owner, str)
        ):
            raise RegistryError(500, "project ownership record invalid")
        return owner

    def claim_owner(self, package: str, owner: str) -> bool:
        path = self.owner_path(package)
        existing = self.read_owner(package)
        if existing is not None:
            if existing != owner:
                raise RegistryError(
                    403,
                    f"Package is owned by another publisher: {existing}",
                )
            return False

        data = {
            "schema": 1,
            "package": package,
            "owner": owner,
        }
        atomic_write(path, canonical_json(data), 0o444)
        return True

    def rollback_owner_claim(self, package: str, owner: str) -> None:
        path = self.owner_path(package)
        try:
            current = self.read_owner(package)
            candidates = self.projects / package / "candidates"
            has_candidates = candidates.is_dir() and any(candidates.iterdir())
            if current == owner and not has_candidates:
                path.unlink(missing_ok=True)
                fsync_dir(path.parent)
        except OSError:
            pass

    def load_staged_record(self, package: str, version: str) -> dict:
        path = self.candidate_path(package, version)
        if not path.is_file():
            raise RegistryError(404, "staged Package version not found")
        try:
            record = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            raise RegistryError(500, f"staged candidate record invalid: {exc}") from exc

        if (
            record.get("schema") != 1
            or record.get("kind") != "asmory-staged-release"
            or record.get("package") != package
            or record.get("version") != version
        ):
            raise RegistryError(500, "staged candidate record invalid")
        return record

    def read_archive_contract(self, candidate: dict) -> dict:
        package = candidate["package"]["name"]
        version = candidate["package"]["version"]
        artifact_meta = candidate["artifact"]
        object_path = self.verify_object(
            artifact_meta["sha256"],
            artifact_meta["size"],
        )

        root_prefix = f"{package}/"
        members: dict[str, tarfile.TarInfo] = {}
        total = 0

        try:
            with tarfile.open(object_path, "r:gz") as tf:
                infos = tf.getmembers()
                if len(infos) > MAX_ARCHIVE_MEMBERS:
                    raise RegistryError(422, "Artifact archive contains too many entries")

                for info in infos:
                    raw_name = info.name
                    if "\\" in raw_name:
                        raise RegistryError(422, "Artifact member uses non-POSIX path")

                    path = PurePosixPath(raw_name)
                    if path.is_absolute() or any(
                        part in ("", ".", "..") for part in path.parts
                    ):
                        raise RegistryError(422, f"unsafe Artifact path: {raw_name!r}")

                    normalized = path.as_posix()
                    if normalized in members:
                        raise RegistryError(422, f"duplicate Artifact path: {normalized}")

                    if not (
                        info.isdir()
                        or info.isreg()
                    ):
                        raise RegistryError(
                            422,
                            f"Artifact contains unsupported member type: {normalized}",
                        )

                    if not (
                        normalized == package
                        or normalized.startswith(root_prefix)
                    ):
                        raise RegistryError(
                            422,
                            "Artifact escapes declared Package root",
                        )

                    if info.isreg():
                        total += info.size
                        if total > self.max_unpacked:
                            raise RegistryError(
                                422,
                                "Artifact unpacked size exceeds Registry limit",
                            )

                    members[normalized] = info

                required = {
                    f"{package}/asm.toml",
                    f"{package}/semantics.toml",
                    f"{package}/conformance/suite.toml",
                }

                for name in required:
                    info = members.get(name)
                    if info is None or not info.isreg():
                        raise RegistryError(
                            422,
                            f"Artifact promotion metadata missing: {name}",
                        )
                    if info.size > MAX_METADATA_FILE:
                        raise RegistryError(
                            422,
                            f"Artifact metadata file too large: {name}",
                        )

                def read_toml(name: str) -> dict:
                    info = members[name]
                    extracted = tf.extractfile(info)
                    if extracted is None:
                        raise RegistryError(422, f"cannot read Artifact metadata: {name}")
                    try:
                        raw = extracted.read(MAX_METADATA_FILE + 1)
                        if len(raw) > MAX_METADATA_FILE:
                            raise RegistryError(
                                422,
                                f"Artifact metadata file too large: {name}",
                            )
                        return tomllib.loads(raw.decode("utf-8"))
                    except (UnicodeDecodeError, tomllib.TOMLDecodeError) as exc:
                        raise RegistryError(
                            422,
                            f"Artifact metadata TOML invalid: {name}: {exc}",
                        ) from exc

                manifest = read_toml(f"{package}/asm.toml")
                semantics = read_toml(f"{package}/semantics.toml")
                suite = read_toml(f"{package}/conformance/suite.toml")

        except tarfile.TarError as exc:
            raise RegistryError(422, f"Artifact archive invalid: {exc}") from exc

        pkg = manifest.get("package")
        if not isinstance(pkg, dict):
            raise RegistryError(422, "asm.toml [package] table missing")
        if pkg.get("name") != package or pkg.get("version") != version:
            raise RegistryError(
                422,
                "Artifact asm.toml Package identity does not match staged candidate",
            )

        sem_ref = manifest.get("semantics")
        if not isinstance(sem_ref, dict):
            raise RegistryError(422, "asm.toml [semantics] table missing")

        if semantics.get("schema") != 1:
            raise RegistryError(422, "semantics.toml schema unsupported")

        capability = semantics.get("capability")
        profile = semantics.get("profile")
        if not isinstance(capability, str) or not capability:
            raise RegistryError(422, "semantic Capability missing")
        if not isinstance(profile, str) or not profile:
            raise RegistryError(422, "semantic Profile missing")

        if (
            sem_ref.get("capability") != capability
            or sem_ref.get("contract") != profile
        ):
            raise RegistryError(
                422,
                "asm.toml semantic identity disagrees with semantics.toml",
            )

        try:
            canonical = canonical_semantics(semantics)
            fingerprint = semantic_fingerprint(semantics)
        except (KeyError, TypeError, ValueError) as exc:
            raise RegistryError(
                422,
                f"semantic Facets cannot be canonicalized: {exc}",
            ) from exc

        target = manifest.get("target")
        if not isinstance(target, dict):
            raise RegistryError(422, "asm.toml [target] table missing")

        for key in ("arch", "os", "object", "abi"):
            if not isinstance(target.get(key), str) or not target[key]:
                raise RegistryError(422, f"target.{key} missing")

        isa = target.get("isa")
        if not isinstance(isa, dict):
            raise RegistryError(422, "asm.toml [target.isa] table missing")

        baseline = isa.get("baseline")
        required_isa = isa.get("required", [])
        optional_isa = isa.get("optional", [])

        if not isinstance(baseline, str) or not baseline:
            raise RegistryError(422, "target.isa.baseline missing")
        if not (
            isinstance(required_isa, list)
            and all(isinstance(x, str) and x for x in required_isa)
        ):
            raise RegistryError(422, "target.isa.required invalid")
        if not (
            isinstance(optional_isa, list)
            and all(isinstance(x, str) and x for x in optional_isa)
        ):
            raise RegistryError(422, "target.isa.optional invalid")

        toolchain = manifest.get("toolchain")
        if not isinstance(toolchain, dict):
            raise RegistryError(422, "asm.toml [toolchain] table missing")
        for key in ("assembler", "min_version", "syntax"):
            if not isinstance(toolchain.get(key), str) or not toolchain[key]:
                raise RegistryError(422, f"toolchain.{key} missing")

        build = manifest.get("build")
        if not isinstance(build, dict):
            raise RegistryError(422, "asm.toml [build] table missing")
        sources = build.get("sources")
        if not (
            isinstance(sources, list)
            and sources
            and all(isinstance(x, str) and x for x in sources)
        ):
            raise RegistryError(422, "build.sources must be a non-empty string array")

        for source in sources:
            rel = safe_relpath(source, "build source")
            full = f"{package}/{rel.as_posix()}"
            info = members.get(full)
            if info is None or not info.isreg():
                raise RegistryError(
                    422,
                    f"declared build source is absent from Artifact: {source}",
                )

        exports = manifest.get("exports")
        if not isinstance(exports, dict) or not exports:
            raise RegistryError(422, "asm.toml exports are missing")

        release_exports = []
        for logical, exported in sorted(exports.items()):
            if not isinstance(logical, str) or not logical:
                raise RegistryError(422, "logical export name invalid")
            if not isinstance(exported, dict):
                raise RegistryError(422, f"export {logical} metadata invalid")
            symbol = exported.get("symbol")
            section = exported.get("section")
            calling = exported.get("calling_convention")
            if not all(isinstance(x, str) and x for x in (symbol, section, calling)):
                raise RegistryError(422, f"export {logical} metadata incomplete")
            release_exports.append(
                {
                    "logical": logical,
                    "symbol": symbol,
                    "section": section,
                    "calling_convention": calling,
                }
            )

        suite_table = suite.get("suite")
        if suite.get("schema") != 1 or not isinstance(suite_table, dict):
            raise RegistryError(422, "conformance suite metadata invalid")

        suite_id = suite_table.get("id")
        suite_profile = suite_table.get("profile")
        runner = suite_table.get("runner")
        facets = suite_table.get("facets")

        if not isinstance(suite_id, str) or not suite_id:
            raise RegistryError(422, "conformance suite id missing")
        if suite_profile != profile:
            raise RegistryError(
                422,
                "conformance suite Profile disagrees with semantic Profile",
            )
        if not isinstance(runner, str) or not runner:
            raise RegistryError(422, "conformance suite runner missing")
        runner_rel = safe_relpath(runner, "conformance runner")
        runner_full = f"{package}/conformance/{runner_rel.as_posix()}"
        info = members.get(runner_full)
        if info is None or not info.isreg():
            raise RegistryError(
                422,
                "declared conformance runner is absent from Artifact",
            )

        if not isinstance(facets, list) or not facets:
            raise RegistryError(422, "conformance suite facet coverage missing")

        facet_paths = []
        for facet in facets:
            if not isinstance(facet, dict):
                raise RegistryError(422, "conformance facet entry invalid")
            path = facet.get("path")
            tests = facet.get("tests")
            if not isinstance(path, str) or not path:
                raise RegistryError(422, "conformance facet path invalid")
            if not (
                isinstance(tests, list)
                and tests
                and all(isinstance(x, str) and x for x in tests)
            ):
                raise RegistryError(422, f"conformance tests missing for {path}")
            facet_paths.append(path)

        origin = candidate.get("origin")
        origin_variant = origin.get("variant") if isinstance(origin, dict) else None
        if isinstance(origin_variant, str) and ID_RE.fullmatch(origin_variant):
            variant_id = origin_variant
        else:
            variant_id = f"{target['arch']}-{baseline}-default"

        variant = {
            "id": variant_id,
            "stability": "experimental",
            "capability": capability,
            "profile": profile,
            "conformance_suite": suite_id,
            "target": {
                "arch": target["arch"],
                "os": target["os"],
                "object": target["object"],
                "abi": target["abi"],
                "isa": {
                    "baseline": baseline,
                    "required": sorted(set(required_isa)),
                    "optional": sorted(set(optional_isa)),
                },
            },
            "toolchain": {
                "assembler": toolchain["assembler"],
                "min_version": toolchain["min_version"],
                "syntax": toolchain["syntax"],
            },
            "exports": release_exports,
        }

        return {
            "capability": capability,
            "profile": profile,
            "semantic_fingerprint": fingerprint,
            "canonical_semantics": canonical,
            "conformance": {
                "suite": suite_id,
                "runner": f"conformance/{runner_rel.as_posix()}",
                "facet_coverage": sorted(set(facet_paths)),
                "execution": "not-registry-executed",
            },
            "variant": variant,
        }

    def derive_active_release(
        self,
        staged_record: dict,
        owner: str,
    ) -> dict:
        candidate = staged_record["candidate"]
        contract = self.read_archive_contract(candidate)
        package = candidate["package"]["name"]
        version = candidate["package"]["version"]
        artifact = candidate["artifact"]

        return {
            "registry": "Asmory",
            "schema": 5,
            "project": package,
            "owner": owner,
            "candidate_sha256": staged_record["candidate_sha256"],
            "resolvable": True,
            "release": {
                "version": version,
                "state": "active",
                "published_at": datetime.now(timezone.utc).replace(
                    microsecond=0
                ).isoformat().replace("+00:00", "Z"),
                "source": candidate["source"],
                "origin": candidate.get("origin"),
                "capability": contract["capability"],
                "profile": contract["profile"],
                "semantic_fingerprint": contract["semantic_fingerprint"],
                "canonical_semantics": contract["canonical_semantics"],
                "conformance": contract["conformance"],
                "review": {
                    "state": "unreviewed",
                    "reviewed_anchor": False,
                },
                "safety": {
                    "state": "normal",
                    "advisories": [],
                },
                "variants": [contract["variant"]],
                "artifacts": [
                    {
                        "kind": artifact["kind"],
                        "filename": artifact["filename"],
                        "content_type": "application/gzip",
                        "size": artifact["size"],
                        "sha256": artifact["sha256"],
                        "download": (
                            f"/api/v1/packages/{package}/{version}/download"
                        ),
                    }
                ],
                "promotion_validation": {
                    "server_derived_from_artifact": True,
                    "package_identity_consistent": True,
                    "semantic_fingerprint_recomputed": True,
                    "machine_contract_declared": True,
                    "source_members_verified": True,
                    "conformance_suite_declared": True,
                    "code_execution": False,
                },
            },
        }


class Handler(BaseHTTPRequestHandler):
    server_version = "AsmoryWrite/0.2"
    protocol_version = "HTTP/1.1"

    @property
    def state(self) -> RegistryState:
        return self.server.state  # type: ignore[attr-defined]

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write(
            f"{self.client_address[0]} {self.command} {self.path} - {fmt % args}\n"
        )

    def send_json(self, status: int, value: dict) -> None:
        body = canonical_json(value)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def send_artifact(self, artifact: dict) -> None:
        obj = self.state.verify_object(
            artifact["sha256"],
            artifact["size"],
        )
        size = obj.stat().st_size
        self.send_response(200)
        self.send_header("Content-Type", "application/gzip")
        self.send_header(
            "Content-Disposition",
            f'attachment; filename="{artifact["filename"]}"',
        )
        self.send_header("Content-Length", str(size))
        self.send_header("Cache-Control", "public, max-age=300")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Connection", "close")
        self.end_headers()
        with obj.open("rb") as f:
            for block in iter(lambda: f.read(1024 * 1024), b""):
                self.wfile.write(block)
        self.close_connection = True

    def fail(self, exc: RegistryError) -> None:
        self.send_json(exc.status, {"error": exc.message})

    def require_owner(self) -> str:
        return self.state.auth_owner(self.headers.get("Authorization"))

    def content_length(self, maximum: int) -> int:
        raw = self.headers.get("Content-Length")
        if raw is None or not raw.isdigit():
            raise RegistryError(411, "Content-Length is required")
        length = int(raw)
        if length > maximum:
            raise RegistryError(413, "request body too large")
        return length

    def read_exact(self, length: int) -> bytes:
        data = self.rfile.read(length)
        if len(data) != length:
            raise RegistryError(400, "request body truncated")
        return data

    def active_get(self, path: str) -> bool:
        versions_match = re.fullmatch(
            r"/api/v1/packages/([a-z0-9][a-z0-9._-]*)/versions",
            path,
        )
        if versions_match:
            package = versions_match.group(1)
            versions = self.state.active_version_summaries(package)
            if not versions:
                raise RegistryError(404, "active Package not found")
            self.send_json(
                200,
                {
                    "registry": "Asmory",
                    "schema": 1,
                    "project": package,
                    "versions": versions,
                },
            )
            return True

        m = re.fullmatch(
            r"/api/v1/packages/([a-z0-9][a-z0-9._-]*)"
            r"(?:/([0-9]+(?:\.[0-9]+){2}(?:[-+][0-9A-Za-z.-]+)?))?"
            r"(/download)?",
            path,
        )
        if not m:
            return False

        package, version, download = m.groups()
        versions = self.state.active_versions_sorted(package)

        if version is None:
            if not versions:
                raise RegistryError(404, "active Package not found")
            summary = self.state.active_project_summary(package)
            summary["versions"] = versions
            self.send_json(
                200,
                {
                    "registry": "Asmory",
                    "schema": 1,
                    "project": summary,
                },
            )
            return True

        record = self.state.load_active_release(package, version)

        if download:
            artifact = record["release"]["artifacts"][0]
            self.send_artifact(artifact)
        else:
            self.send_json(200, record)
        return True

    def do_GET(self) -> None:
        try:
            path = urlsplit(self.path).path

            if path == "/healthz":
                self.send_json(
                    200,
                    {
                        "status": "ok",
                        "service": "asmory-registry-write",
                        "promotion": True,
                        "active_index": True,
                    },
                )
                return

            if path == "/api/v1/packages":
                parsed = urlsplit(self.path)
                params = parse_qs(parsed.query, keep_blank_values=False)

                def one(name: str) -> str | None:
                    values = params.get(name)
                    if not values:
                        return None
                    if len(values) != 1:
                        raise RegistryError(400, f"duplicate query parameter: {name}")
                    return values[0]

                q = one("q")
                capability = one("capability")
                arch = one("arch")
                raw_limit = one("limit") or "50"

                if not raw_limit.isdigit():
                    raise RegistryError(400, "limit must be an integer")
                limit = int(raw_limit)
                if not 1 <= limit <= 100:
                    raise RegistryError(400, "limit must be in [1, 100]")

                packages = self.state.search_active_packages(
                    q,
                    capability,
                    arch,
                    limit,
                )
                self.send_json(
                    200,
                    {
                        "registry": "Asmory",
                        "schema": 1,
                        "query": {
                            "q": q,
                            "capability": capability,
                            "arch": arch,
                            "limit": limit,
                        },
                        "count": len(packages),
                        "packages": packages,
                    },
                )
                return

            if self.active_get(path):
                return

            owner = self.require_owner()

            m = re.fullmatch(
                r"/api/v1/staging/packages/([a-z0-9][a-z0-9._-]*)/"
                r"([0-9]+(?:\.[0-9]+){2}(?:[-+][0-9A-Za-z.-]+)?)(/download)?",
                path,
            )
            if not m:
                raise RegistryError(404, "resource not found")

            package, version, download = m.groups()
            project_owner = self.state.read_owner(package)
            if project_owner is None:
                raise RegistryError(404, "staged Package not found")
            if project_owner != owner:
                raise RegistryError(403, "publisher does not own staged Package")

            record = self.state.load_staged_record(package, version)

            if download:
                self.send_artifact(record["candidate"]["artifact"])
            else:
                self.send_json(200, record)

        except RegistryError as exc:
            self.fail(exc)
        except OSError as exc:
            self.fail(RegistryError(500, f"storage failure: {exc}"))

    def do_PUT(self) -> None:
        temp = None
        try:
            owner = self.require_owner()
            path = urlsplit(self.path).path
            m = re.fullmatch(
                r"/api/v1/staging/artifacts/sha256/([0-9a-f]{64})",
                path,
            )
            if not m:
                raise RegistryError(404, "Artifact staging endpoint not found")

            digest = m.group(1)
            length = self.content_length(self.state.max_artifact)
            final = self.state.object_path(digest)

            if final.exists():
                obj = self.state.verify_object(digest, length)
                self.send_json(
                    200,
                    {
                        "state": "reused",
                        "sha256": digest,
                        "size": obj.stat().st_size,
                        "owner": owner,
                    },
                )
                return

            fd, name = tempfile.mkstemp(
                prefix=f"{digest}.",
                dir=self.state.incoming,
            )
            temp = Path(name)

            h = hashlib.sha256()
            remaining = length

            try:
                with os.fdopen(fd, "wb", closefd=True) as out:
                    while remaining:
                        block = self.rfile.read(min(1024 * 1024, remaining))
                        if not block:
                            raise RegistryError(400, "Artifact upload truncated")
                        out.write(block)
                        h.update(block)
                        remaining -= len(block)
                    out.flush()
                    os.fsync(out.fileno())

                if h.hexdigest() != digest:
                    raise RegistryError(422, "Artifact SHA-256 mismatch")

                os.chmod(temp, 0o444)

                try:
                    os.link(temp, final)
                    fsync_dir(final.parent)
                    state = "stored"
                    status = 201
                except FileExistsError:
                    self.state.verify_object(digest, length)
                    state = "reused"
                    status = 200

                self.send_json(
                    status,
                    {
                        "state": state,
                        "sha256": digest,
                        "size": length,
                        "owner": owner,
                    },
                )
            finally:
                temp.unlink(missing_ok=True)
                temp = None

        except RegistryError as exc:
            self.fail(exc)
        except OSError as exc:
            self.fail(RegistryError(500, f"storage failure: {exc}"))
        finally:
            if temp is not None:
                temp.unlink(missing_ok=True)

    def do_POST(self) -> None:
        try:
            owner = self.require_owner()
            path = urlsplit(self.path).path

            if path == "/api/v1/staging/releases":
                self.stage_candidate(owner)
                return

            if path == "/api/v1/staging/promote":
                self.promote_candidate(owner)
                return

            raise RegistryError(404, "publication write endpoint not found")

        except RegistryError as exc:
            self.fail(exc)
        except OSError as exc:
            self.fail(RegistryError(500, f"storage failure: {exc}"))

    def stage_candidate(self, owner: str) -> None:
        length = self.content_length(MAX_CANDIDATE)
        raw = self.read_exact(length)
        candidate = self.state.validate_candidate(raw)

        package = candidate["package"]["name"]
        version = candidate["package"]["version"]
        artifact = candidate["artifact"]

        self.state.verify_object(artifact["sha256"], artifact["size"])
        candidate_sha = hashlib.sha256(raw).hexdigest()

        with self.state.project_lock(package):
            claimed = self.state.claim_owner(package, owner)
            record_path = self.state.candidate_path(package, version)

            record = {
                "schema": 1,
                "kind": "asmory-staged-release",
                "state": "staged",
                "resolvable": False,
                "owner": owner,
                "package": package,
                "version": version,
                "candidate_sha256": candidate_sha,
                "artifact_sha256": artifact["sha256"],
                "candidate": candidate,
            }
            body = canonical_json(record)

            try:
                if record_path.exists():
                    existing = record_path.read_bytes()
                    if existing != body:
                        raise RegistryError(
                            409,
                            "immutable staged Package version already exists with different candidate",
                        )
                    status = 200
                    state = "reused"
                else:
                    atomic_write(record_path, body, 0o444)
                    status = 201
                    state = "stored"
            except Exception:
                if claimed:
                    self.state.rollback_owner_claim(package, owner)
                raise

        self.send_json(
            status,
            {
                "state": state,
                "package": package,
                "version": version,
                "owner": owner,
                "candidate_sha256": candidate_sha,
                "artifact_sha256": artifact["sha256"],
                "resolvable": False,
            },
        )

    def promote_candidate(self, owner: str) -> None:
        length = self.content_length(MAX_PROMOTION_REQUEST)
        raw = self.read_exact(length)

        try:
            request = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise RegistryError(400, f"promotion request JSON invalid: {exc}") from exc

        if not isinstance(request, dict) or canonical_json(request) != raw:
            raise RegistryError(400, "promotion request must be canonical JSON")

        if (
            request.get("schema") != 1
            or request.get("kind") != "asmory-promotion-request"
        ):
            raise RegistryError(400, "unsupported promotion request")

        package = request.get("package")
        version = request.get("version")
        candidate_sha = request.get("candidate_sha256")

        if not isinstance(package, str) or NAME_RE.fullmatch(package) is None:
            raise RegistryError(400, "promotion Package name invalid")
        if not isinstance(version, str) or VERSION_RE.fullmatch(version) is None:
            raise RegistryError(400, "promotion Package version invalid")
        if not isinstance(candidate_sha, str) or SHA_RE.fullmatch(candidate_sha) is None:
            raise RegistryError(400, "promotion candidate SHA-256 invalid")

        with self.state.project_lock(package):
            project_owner = self.state.read_owner(package)
            if project_owner is None:
                raise RegistryError(404, "Package ownership/staging state not found")
            if project_owner != owner:
                raise RegistryError(403, "publisher does not own Package")

            staged = self.state.load_staged_record(package, version)
            if staged["owner"] != owner:
                raise RegistryError(403, "publisher does not own staged candidate")
            if staged["candidate_sha256"] != candidate_sha:
                raise RegistryError(
                    409,
                    "promotion request does not match immutable staged candidate",
                )

            active_path = self.state.active_release_path(package, version)

            if active_path.exists():
                try:
                    existing = json.loads(active_path.read_text())
                except (OSError, json.JSONDecodeError) as exc:
                    raise RegistryError(
                        500,
                        f"active Release record invalid: {exc}",
                    ) from exc

                if existing.get("candidate_sha256") != candidate_sha:
                    raise RegistryError(
                        409,
                        "active Package version already exists with different candidate",
                    )

                record = existing
                state = "reused"
                status = 200
            else:
                record = self.state.derive_active_release(staged, owner)
                atomic_write(active_path, canonical_json(record), 0o444)
                self.state.rebuild_active_index()
                state = "promoted"
                status = 201

        self.send_json(
            status,
            {
                "state": state,
                "package": package,
                "version": version,
                "owner": owner,
                "candidate_sha256": candidate_sha,
                "artifact_sha256": staged["artifact_sha256"],
                "semantic_fingerprint": record["release"]["semantic_fingerprint"],
                "variant": record["release"]["variants"][0]["id"],
                "resolvable": True,
                "release": f"/api/v1/packages/{package}/{version}",
            },
        )


def parse_args():
    import argparse

    parser = argparse.ArgumentParser(prog="asmory-registry-write")
    parser.add_argument(
        "--host",
        default=os.environ.get("ASMORY_WRITE_HOST", "127.0.0.1"),
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("ASMORY_WRITE_PORT", "18081")),
    )
    parser.add_argument(
        "--data-dir",
        default=os.environ.get("ASMORY_WRITE_DATA_DIR", "build/write-registry"),
    )
    parser.add_argument(
        "--auth-file",
        default=os.environ.get(
            "ASMORY_WRITE_AUTH_FILE",
            "build/write-registry-auth.json",
        ),
    )
    parser.add_argument(
        "--max-artifact-bytes",
        type=int,
        default=int(
            os.environ.get(
                "ASMORY_WRITE_MAX_ARTIFACT_BYTES",
                str(DEFAULT_MAX_ARTIFACT),
            )
        ),
    )
    parser.add_argument(
        "--max-unpacked-bytes",
        type=int,
        default=int(
            os.environ.get(
                "ASMORY_WRITE_MAX_UNPACKED_BYTES",
                str(DEFAULT_MAX_UNPACKED),
            )
        ),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if not (1 <= args.port <= 65535):
        raise SystemExit("invalid port")
    if args.max_artifact_bytes <= 0:
        raise SystemExit("max Artifact size must be positive")
    if args.max_unpacked_bytes <= 0:
        raise SystemExit("max unpacked size must be positive")

    state = RegistryState(
        Path(args.data_dir).resolve(),
        Path(args.auth_file).resolve(),
        args.max_artifact_bytes,
        args.max_unpacked_bytes,
    )

    class Server(ThreadingHTTPServer):
        daemon_threads = True
        allow_reuse_address = True

    server = Server((args.host, args.port), Handler)
    server.state = state  # type: ignore[attr-defined]

    print(
        f"asmory-registry-write listening on {args.host}:{args.port} "
        f"data={state.data_dir}",
        flush=True,
    )

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
