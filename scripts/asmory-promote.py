#!/usr/bin/env python3
from __future__ import annotations

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
from urllib.parse import urlsplit

SHA_RE = __import__("re").compile(r"[0-9a-f]{64}")


class PromoteError(RuntimeError):
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
        raise PromoteError(f"command failed: {' '.join(args)}: {exc}") from exc


def canonical_json(value: dict) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode("utf-8")


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


def endpoint() -> tuple[str, str, int, str]:
    raw = os.environ.get(
        "ASMORY_PUBLISH_URL",
        "http://127.0.0.1:18081",
    ).strip()
    parsed = urlsplit(raw)

    if parsed.scheme not in ("http", "https"):
        raise PromoteError("ASMORY_PUBLISH_URL must use http or https")
    if parsed.username is not None or parsed.password is not None:
        raise PromoteError("credentials must not be embedded in ASMORY_PUBLISH_URL")
    if not parsed.hostname:
        raise PromoteError("ASMORY_PUBLISH_URL has no host")
    if parsed.query or parsed.fragment:
        raise PromoteError("ASMORY_PUBLISH_URL must not contain query/fragment")
    if parsed.scheme == "http" and not _loopback_host(parsed.hostname):
        raise PromoteError(
            "plaintext HTTP promotion is allowed only for loopback development endpoints"
        )

    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    return parsed.scheme, parsed.hostname, port, parsed.path.rstrip("/")


def token() -> str:
    raw = os.environ.get("ASMORY_PUBLISH_TOKEN_FILE")
    path = (
        Path(raw).expanduser()
        if raw
        else Path.home() / ".config" / "asmory" / "publish-token"
    )

    try:
        st = path.lstat()
    except OSError as exc:
        raise PromoteError(f"cannot read publication token file: {path}: {exc}") from exc

    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode):
        raise PromoteError("publication token path must be a regular non-symlink file")
    if stat.S_IMODE(st.st_mode) & 0o077:
        raise PromoteError(
            "publication token file must not be readable/writable by group or others"
        )

    value = path.read_text().strip()
    if not (32 <= len(value) <= 512) or any(c.isspace() for c in value):
        raise PromoteError("publication token format is invalid")
    return value


def connection(
    scheme: str,
    host: str,
    port: int,
) -> http.client.HTTPConnection:
    timeout = float(os.environ.get("ASMORY_PUBLISH_TIMEOUT", "30"))
    if timeout <= 0 or timeout > 600:
        raise PromoteError("ASMORY_PUBLISH_TIMEOUT must be in (0, 600]")

    if scheme == "https":
        return http.client.HTTPSConnection(
            host,
            port,
            timeout=timeout,
            context=ssl.create_default_context(),
        )
    return http.client.HTTPConnection(host, port, timeout=timeout)


def workspace_root() -> Path:
    root = Path.cwd().resolve()
    if not (root / "asmory.workspace.toml").is_file():
        raise PromoteError("no repository workspace")
    return root


def workspace_meta(root: Path, package: str) -> dict:
    try:
        return json.loads(
            run(["asmory-workspace", "metadata", package], cwd=root).stdout
        )
    except json.JSONDecodeError as exc:
        raise PromoteError(f"workspace helper returned invalid JSON: {exc}") from exc


def candidate(root: Path, package: str) -> tuple[dict, bytes]:
    # Local publish-prepare is re-run first. This is intentionally not the
    # remote staging command; promotion still requires a previously staged
    # immutable candidate on the Registry.
    run(["asmory-publish", package], cwd=root)

    meta = workspace_meta(root, package)
    version = meta.get("version")
    if meta.get("name") != package or not isinstance(version, str):
        raise PromoteError("workspace Package identity mismatch")

    path = (
        root
        / ".asmory"
        / ".publish"
        / package
        / version
        / "release-candidate.json"
    )

    if not path.is_file():
        raise PromoteError("local release candidate is missing")

    raw = path.read_bytes()

    try:
        obj = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise PromoteError(f"local release candidate JSON invalid: {exc}") from exc

    canonical = canonical_json(obj)
    if canonical != raw:
        raise PromoteError("local release candidate is not canonical JSON")

    return obj, raw


def promote(root: Path, package: str) -> int:
    obj, raw = candidate(root, package)
    candidate_sha = hashlib.sha256(raw).hexdigest()

    if SHA_RE.fullmatch(candidate_sha) is None:
        raise PromoteError("candidate digest computation failed")

    package_meta = obj.get("package", {})
    version = package_meta.get("version")

    request = {
        "schema": 1,
        "kind": "asmory-promotion-request",
        "package": package,
        "version": version,
        "candidate_sha256": candidate_sha,
    }
    body = canonical_json(request)

    scheme, host, port, base = endpoint()
    auth = token()

    path = f"{base}/api/v1/staging/promote" if base else "/api/v1/staging/promote"
    conn = connection(scheme, host, port)

    try:
        conn.request(
            "POST",
            path,
            body=body,
            headers={
                "Authorization": f"Bearer {auth}",
                "Content-Type": "application/json",
                "Content-Length": str(len(body)),
                "Connection": "close",
            },
        )
        response = conn.getresponse()
        response_raw = response.read(1024 * 1024 + 1)
    except (OSError, http.client.HTTPException) as exc:
        raise PromoteError(f"promotion transport failed: {exc}") from exc
    finally:
        conn.close()

    if len(response_raw) > 1024 * 1024:
        raise PromoteError("Registry promotion response exceeds 1 MiB")

    try:
        data = json.loads(response_raw) if response_raw else {}
    except json.JSONDecodeError as exc:
        raise PromoteError(
            f"Registry returned non-JSON promotion response ({response.status})"
        ) from exc

    if response.status not in (200, 201):
        message = data.get("error", "promotion rejected")
        raise PromoteError(f"Registry rejected promotion ({response.status}): {message}")

    if (
        data.get("package") != package
        or data.get("version") != version
        or data.get("candidate_sha256") != candidate_sha
        or data.get("resolvable") is not True
    ):
        raise PromoteError("Registry promotion acknowledgement mismatches local identity")

    print("Release promoted")
    print()
    print(f"  package      {package}@{version}")
    print(f"  candidate    {candidate_sha}")
    print(f"  artifact     {data.get('artifact_sha256', '?')}")
    print(f"  semantics    {data.get('semantic_fingerprint', '?')}")
    print(f"  variant      {data.get('variant', '?')}")
    print(f"  state        {data.get('state', '?')}")
    print("  resolvable   yes")
    print(f"  release      {data.get('release', '?')}")
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: asmory-promote <package>", file=sys.stderr)
        return 2

    try:
        return promote(workspace_root(), sys.argv[1])
    except PromoteError as exc:
        print(f"promote: {exc}", file=sys.stderr)
        return 26


if __name__ == "__main__":
    raise SystemExit(main())
