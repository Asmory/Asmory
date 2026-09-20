#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import os
from pathlib import Path
import socket
import ssl
import stat
import subprocess
import sys
import tempfile
import tomllib
from urllib.parse import urlsplit


class PublishError(RuntimeError):
    pass


class RemotePublishError(PublishError):
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


def workspace_metadata(root: Path, package: str) -> dict:
    try:
        return json.loads(
            run(["asmory-workspace", "metadata", package], cwd=root).stdout
        )
    except json.JSONDecodeError as exc:
        raise PublishError(f"workspace helper returned invalid metadata JSON: {exc}") from exc


def candidate_paths(root: Path, package: str) -> tuple[Path, Path, Path]:
    meta = workspace_metadata(root, package)
    name = meta.get("name")
    version = meta.get("version")

    if name != package or not isinstance(version, str) or not version:
        raise PublishError("workspace Package identity mismatch")

    base = root / ".asmory" / ".publish" / name / version
    candidate = base / "release-candidate.json"
    artifact = base / f"{name}-{version}.tar.gz"
    return base, candidate, artifact


def prepare(root: Path, package: str) -> int:
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
    print("  next         authenticated Registry staging upload")
    return 0


def _loopback_host(host: str) -> bool:
    if host.lower() == "localhost":
        return True

    try:
        infos = socket.getaddrinfo(host, None, type=socket.SOCK_STREAM)
    except socket.gaierror:
        return False

    if not infos:
        return False

    for info in infos:
        address = info[4][0]
        if address == "::1" or address.startswith("127."):
            continue
        return False

    return True


def _registry_endpoint() -> tuple[str, str, int, str]:
    raw = os.environ.get(
        "ASMORY_PUBLISH_URL",
        "http://127.0.0.1:18081",
    ).strip()

    parsed = urlsplit(raw)

    if parsed.scheme not in ("http", "https"):
        raise RemotePublishError("ASMORY_PUBLISH_URL must use http or https")

    if parsed.username is not None or parsed.password is not None:
        raise RemotePublishError("credentials must not be embedded in ASMORY_PUBLISH_URL")

    if not parsed.hostname:
        raise RemotePublishError("ASMORY_PUBLISH_URL has no host")

    if parsed.query or parsed.fragment:
        raise RemotePublishError("ASMORY_PUBLISH_URL must not contain query/fragment")

    if parsed.scheme == "http" and not _loopback_host(parsed.hostname):
        raise RemotePublishError(
            "plaintext HTTP publication is allowed only for loopback development endpoints"
        )

    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    base = parsed.path.rstrip("/")
    return parsed.scheme, parsed.hostname, port, base


def _token_file() -> Path:
    raw = os.environ.get("ASMORY_PUBLISH_TOKEN_FILE")
    path = (
        Path(raw).expanduser()
        if raw
        else Path.home() / ".config" / "asmory" / "publish-token"
    )

    try:
        st = path.lstat()
    except OSError as exc:
        raise RemotePublishError(f"cannot read publication token file: {path}: {exc}") from exc

    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode):
        raise RemotePublishError("publication token path must be a regular non-symlink file")

    if stat.S_IMODE(st.st_mode) & 0o077:
        raise RemotePublishError(
            "publication token file must not be readable/writable by group or others"
        )

    token = path.read_text().strip()

    if not (32 <= len(token) <= 512):
        raise RemotePublishError("publication token length is invalid")

    if any(c.isspace() for c in token):
        raise RemotePublishError("publication token must not contain whitespace")

    return path


def _read_token(path: Path) -> str:
    return path.read_text().strip()


def _connection(
    scheme: str,
    host: str,
    port: int,
) -> http.client.HTTPConnection:
    timeout = float(os.environ.get("ASMORY_PUBLISH_TIMEOUT", "30"))

    if timeout <= 0 or timeout > 600:
        raise RemotePublishError("ASMORY_PUBLISH_TIMEOUT must be in (0, 600]")

    if scheme == "https":
        context = ssl.create_default_context()
        return http.client.HTTPSConnection(host, port, timeout=timeout, context=context)

    return http.client.HTTPConnection(host, port, timeout=timeout)


def _response_json(response: http.client.HTTPResponse) -> tuple[int, dict]:
    raw = response.read(1024 * 1024 + 1)

    if len(raw) > 1024 * 1024:
        raise RemotePublishError("Registry response exceeds 1 MiB")

    try:
        data = json.loads(raw) if raw else {}
    except json.JSONDecodeError as exc:
        raise RemotePublishError(
            f"Registry returned non-JSON response with status {response.status}"
        ) from exc

    if not isinstance(data, dict):
        raise RemotePublishError("Registry response JSON is not an object")

    return response.status, data


def _path(base: str, suffix: str) -> str:
    return f"{base}{suffix}" if base else suffix


def _put_artifact(
    scheme: str,
    host: str,
    port: int,
    base: str,
    token: str,
    artifact: Path,
    digest: str,
) -> dict:
    size = artifact.stat().st_size
    conn = _connection(scheme, host, port)
    path = _path(base, f"/api/v1/staging/artifacts/sha256/{digest}")

    try:
        conn.putrequest("PUT", path)
        conn.putheader("Host", host)
        conn.putheader("Authorization", f"Bearer {token}")
        conn.putheader("Content-Type", "application/gzip")
        conn.putheader("Content-Length", str(size))
        conn.putheader("Connection", "close")
        conn.endheaders()

        with artifact.open("rb") as f:
            for block in iter(lambda: f.read(1024 * 1024), b""):
                conn.send(block)

        status, data = _response_json(conn.getresponse())
    except (OSError, http.client.HTTPException) as exc:
        raise RemotePublishError(f"Artifact upload transport failed: {exc}") from exc
    finally:
        conn.close()

    if status not in (200, 201):
        message = data.get("error", "artifact upload rejected")
        raise RemotePublishError(f"Registry rejected Artifact ({status}): {message}")

    if data.get("sha256") != digest or data.get("size") != size:
        raise RemotePublishError("Registry Artifact acknowledgement does not match upload")

    return data


def _post_candidate(
    scheme: str,
    host: str,
    port: int,
    base: str,
    token: str,
    candidate_bytes: bytes,
) -> dict:
    conn = _connection(scheme, host, port)
    path = _path(base, "/api/v1/staging/releases")

    try:
        conn.request(
            "POST",
            path,
            body=candidate_bytes,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
                "Content-Length": str(len(candidate_bytes)),
                "Connection": "close",
            },
        )
        status, data = _response_json(conn.getresponse())
    except (OSError, http.client.HTTPException) as exc:
        raise RemotePublishError(f"Candidate upload transport failed: {exc}") from exc
    finally:
        conn.close()

    if status not in (200, 201):
        message = data.get("error", "candidate upload rejected")
        raise RemotePublishError(f"Registry rejected candidate ({status}): {message}")

    return data


def remote_publish(root: Path, package: str) -> int:
    # Re-run prepare to prove the candidate still represents the clean current
    # Package commit. Existing identical preparation is idempotent.
    prepare(root, package)

    _, candidate_path, artifact = candidate_paths(root, package)

    if not candidate_path.is_file() or not artifact.is_file():
        raise RemotePublishError("publication candidate is incomplete")

    try:
        candidate = json.loads(candidate_path.read_text())
    except json.JSONDecodeError as exc:
        raise RemotePublishError(f"local candidate JSON is invalid: {exc}") from exc

    candidate_bytes = canonical_json(candidate)

    if candidate_path.read_bytes() != candidate_bytes:
        raise RemotePublishError("local publication candidate is not canonical JSON")

    artifact_meta = candidate.get("artifact", {})
    digest = artifact_meta.get("sha256")
    expected_size = artifact_meta.get("size")

    if not isinstance(digest, str) or len(digest) != 64:
        raise RemotePublishError("local candidate Artifact digest is invalid")

    if sha256_file(artifact) != digest:
        raise RemotePublishError("local candidate Artifact bytes do not match digest")

    if artifact.stat().st_size != expected_size:
        raise RemotePublishError("local candidate Artifact size does not match metadata")

    token_path = _token_file()
    token = _read_token(token_path)
    scheme, host, port, base = _registry_endpoint()

    artifact_result = _put_artifact(
        scheme,
        host,
        port,
        base,
        token,
        artifact,
        digest,
    )

    candidate_result = _post_candidate(
        scheme,
        host,
        port,
        base,
        token,
        candidate_bytes,
    )

    package_meta = candidate.get("package", {})
    name = package_meta.get("name")
    version = package_meta.get("version")

    if (
        candidate_result.get("package") != name
        or candidate_result.get("version") != version
        or candidate_result.get("artifact_sha256") != digest
    ):
        raise RemotePublishError("Registry candidate acknowledgement mismatches local identity")

    print("Publication candidate uploaded")
    print()
    print(f"  package      {name}@{version}")
    print(f"  artifact     {digest}")
    print(f"  object       {artifact_result.get('state', '?')}")
    print(f"  owner        {candidate_result.get('owner', '?')}")
    print(f"  remote       {scheme}://{host}:{port}{base}")
    print(f"  state        {candidate_result.get('state', 'staged')}")
    print("  resolvable   no")
    print("  next         validate full Release/Variant metadata, then promote")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="asmory-publish")
    parser.add_argument("--remote", action="store_true")
    parser.add_argument("package")
    args = parser.parse_args()

    try:
        root = workspace_root()

        if args.remote:
            return remote_publish(root, args.package)

        return prepare(root, args.package)

    except RemotePublishError as exc:
        print(f"publish: {exc}", file=sys.stderr)
        return 24
    except (PublishError, OSError, tomllib.TOMLDecodeError) as exc:
        print(f"publish-prepare: {exc}", file=sys.stderr)
        return 23


if __name__ == "__main__":
    raise SystemExit(main())
