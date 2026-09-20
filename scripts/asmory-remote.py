#!/usr/bin/env python3
from __future__ import annotations

import argparse
import http.client
import json
import os
from pathlib import Path
import platform
import re
import socket
import ssl
import subprocess
import sys
from urllib.parse import quote, urlencode, urlsplit

NAME_RE = re.compile(r"[a-z0-9][a-z0-9._-]*")
SHA_RE = re.compile(r"[0-9a-f]{64}")
BASELINE_ORDER = {
    "x86-64-v1": 1,
    "x86-64-v2": 2,
    "x86-64-v3": 3,
    "x86-64-v4": 4,
}
MAX_RESPONSE = 4 * 1024 * 1024


class RemoteError(RuntimeError):
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
        detail = ""
        if isinstance(exc, subprocess.CalledProcessError):
            detail = (exc.stderr or exc.stdout or "").strip()
        suffix = f": {detail}" if detail else f": {exc}"
        raise RemoteError(f"command failed: {' '.join(args)}{suffix}") from exc


def loopback_host(host: str) -> bool:
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
        "ASMORY_REGISTRY_URL",
        "http://127.0.0.1:18081",
    ).strip()
    parsed = urlsplit(raw)

    if parsed.scheme not in ("http", "https"):
        raise RemoteError("ASMORY_REGISTRY_URL must use http or https")
    if parsed.username is not None or parsed.password is not None:
        raise RemoteError("credentials must not be embedded in ASMORY_REGISTRY_URL")
    if not parsed.hostname:
        raise RemoteError("ASMORY_REGISTRY_URL has no host")
    if parsed.query or parsed.fragment:
        raise RemoteError("ASMORY_REGISTRY_URL must not contain query/fragment")
    if parsed.scheme == "http" and not loopback_host(parsed.hostname):
        raise RemoteError(
            "plaintext HTTP registry access is allowed only for loopback development endpoints"
        )

    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    return parsed.scheme, parsed.hostname, port, parsed.path.rstrip("/")


def connection(
    scheme: str,
    host: str,
    port: int,
) -> http.client.HTTPConnection:
    timeout = float(os.environ.get("ASMORY_REGISTRY_TIMEOUT", "15"))
    if timeout <= 0 or timeout > 300:
        raise RemoteError("ASMORY_REGISTRY_TIMEOUT must be in (0, 300]")

    if scheme == "https":
        return http.client.HTTPSConnection(
            host,
            port,
            timeout=timeout,
            context=ssl.create_default_context(),
        )

    return http.client.HTTPConnection(host, port, timeout=timeout)


def get_json(path: str, query: dict[str, str] | None = None) -> dict:
    scheme, host, port, base = endpoint()
    request_path = f"{base}{path}" if base else path
    if query:
        request_path += "?" + urlencode(query)

    conn = connection(scheme, host, port)
    try:
        conn.request(
            "GET",
            request_path,
            headers={
                "Accept": "application/json",
                "Connection": "close",
            },
        )
        response = conn.getresponse()
        body = response.read(MAX_RESPONSE + 1)
    except (OSError, http.client.HTTPException) as exc:
        raise RemoteError(f"Registry transport failed: {exc}") from exc
    finally:
        conn.close()

    if len(body) > MAX_RESPONSE:
        raise RemoteError("Registry response exceeds 4 MiB")

    try:
        data = json.loads(body) if body else {}
    except json.JSONDecodeError as exc:
        raise RemoteError(
            f"Registry returned non-JSON response ({response.status})"
        ) from exc

    if response.status != 200:
        message = data.get("error", "Registry request failed") if isinstance(data, dict) else "Registry request failed"
        raise RemoteError(f"Registry request failed ({response.status}): {message}")

    if not isinstance(data, dict):
        raise RemoteError("Registry response JSON is not an object")

    return data


def require_name(package: str) -> str:
    if NAME_RE.fullmatch(package) is None:
        raise RemoteError("invalid Package name")
    return package


def parse_target() -> dict:
    out = run(["asmory", "target"]).stdout
    target: dict[str, object] = {"features": set()}

    in_features = False
    for raw in out.splitlines():
        line = raw.rstrip()
        stripped = line.strip()

        if stripped == "features":
            in_features = True
            continue

        if stripped in ("Target", "ISA"):
            in_features = False
            continue

        m = re.match(r"^\s{2}(arch|os|object|abi|baseline)\s+(\S+)\s*$", line)
        if m:
            target[m.group(1)] = m.group(2)
            continue

        if in_features:
            m = re.match(r"^\s{4}([A-Za-z0-9._+-]+)\s+(yes|no)\s*$", line)
            if m and m.group(2) == "yes":
                target["features"].add(m.group(1).lower())

    required = ("arch", "os", "object", "abi", "baseline")
    missing = [key for key in required if key not in target]
    if missing:
        raise RemoteError(
            "cannot parse local Asmory host target: " + ", ".join(missing)
        )

    return target


def compatible_variant(variant: dict, host: dict) -> tuple[bool, str]:
    target = variant.get("target")
    if not isinstance(target, dict):
        return False, "Variant target metadata missing"

    for key in ("arch", "os", "object", "abi"):
        value = target.get(key)
        if value != host.get(key):
            return False, f"{key} requires {value}, host is {host.get(key)}"

    isa = target.get("isa")
    if not isinstance(isa, dict):
        return False, "Variant ISA metadata missing"

    baseline = isa.get("baseline")
    host_baseline = host.get("baseline")
    if baseline in BASELINE_ORDER and host_baseline in BASELINE_ORDER:
        if BASELINE_ORDER[host_baseline] < BASELINE_ORDER[baseline]:
            return False, f"baseline requires {baseline}, host is {host_baseline}"
    elif baseline != host_baseline:
        return False, f"baseline requires {baseline}, host is {host_baseline}"

    required = isa.get("required", [])
    if not isinstance(required, list) or not all(isinstance(x, str) for x in required):
        return False, "Variant required ISA list invalid"

    features = host["features"]
    missing = sorted({x.lower() for x in required} - features)
    if missing:
        return False, "missing ISA: " + ", ".join(missing)

    return True, "compatible"


def version_key(version: str):
    m = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(.*)", version)
    if m is None:
        return (0, 0, 0, 0, version)
    suffix = m.group(4)
    # Stable releases sort after prerelease suffixes at the same numeric core.
    return (
        int(m.group(1)),
        int(m.group(2)),
        int(m.group(3)),
        1 if suffix == "" else 0,
        suffix,
    )


def versions(package: str) -> list[dict]:
    package = require_name(package)
    data = get_json(f"/api/v1/packages/{quote(package, safe='')}/versions")
    values = data.get("versions")
    if not isinstance(values, list):
        raise RemoteError("Registry versions response is malformed")

    result = []
    for item in values:
        if not isinstance(item, dict):
            raise RemoteError("Registry version record is malformed")
        if item.get("version") is None:
            raise RemoteError("Registry version record has no version")
        result.append(item)

    if not result:
        raise RemoteError(f"Package has no active Releases: {package}")

    return sorted(result, key=lambda item: version_key(str(item["version"])), reverse=True)


def release(package: str, version: str | None = None) -> dict:
    package = require_name(package)
    if version is None:
        version = str(versions(package)[0]["version"])

    data = get_json(
        f"/api/v1/packages/{quote(package, safe='')}/{quote(version, safe='')}"
    )

    if data.get("project") != package or data.get("resolvable") is not True:
        raise RemoteError("Registry active Release identity is malformed")

    rel = data.get("release")
    if not isinstance(rel, dict) or rel.get("version") != version:
        raise RemoteError("Registry active Release payload is malformed")

    return data


def select_variant(record: dict) -> tuple[dict, list[tuple[str, str]]]:
    rel = record["release"]
    variants = rel.get("variants")
    if not isinstance(variants, list) or not variants:
        raise RemoteError("active Release has no Variants")

    host = parse_target()
    failures: list[tuple[str, str]] = []
    compatible: list[dict] = []

    for variant in variants:
        if not isinstance(variant, dict):
            continue
        ok, reason = compatible_variant(variant, host)
        vid = str(variant.get("id", "<unknown>"))
        if ok:
            compatible.append(variant)
        else:
            failures.append((vid, reason))

    if not compatible:
        detail = "; ".join(f"{vid}: {reason}" for vid, reason in failures)
        raise RemoteError(
            "no compatible active Variant for this host"
            + (f" ({detail})" if detail else "")
        )

    # Compatibility first. Stable is preferred over experimental; otherwise
    # preserve deterministic Registry ordering by Variant id.
    compatible.sort(
        key=lambda v: (
            0 if v.get("stability") == "stable" else 1,
            str(v.get("id", "")),
        )
    )
    return compatible[0], failures


def command_search(query: str | None) -> int:
    params = {"limit": "50"}
    if query:
        params["q"] = query

    data = get_json("/api/v1/packages", params)
    packages = data.get("packages")
    if not isinstance(packages, list):
        raise RemoteError("Registry search response is malformed")

    print("Remote Asmory index")
    print()
    print("NAME                 VERSION      CAPABILITY               ARCH      OWNER")

    for item in packages:
        if not isinstance(item, dict):
            continue
        print(
            f"{str(item.get('name','')):<20} "
            f"{str(item.get('latest_version','')):<12} "
            f"{str(item.get('capability','')):<24} "
            f"{str(item.get('arch','')):<9} "
            f"{str(item.get('owner',''))}"
        )

    print()
    print(f"matches: {len(packages)}")
    return 0


def command_versions(package: str) -> int:
    values = versions(package)
    print(f"{package} active Releases")
    print()
    print("VERSION      STATE    VARIANTS  ARTIFACT")
    for item in values:
        print(
            f"{str(item.get('version','')):<12} "
            f"{str(item.get('state','active')):<8} "
            f"{str(item.get('variants', item.get('variant_count',''))):<9} "
            f"{str(item.get('artifact_sha256',''))}"
        )
    return 0


def command_info(package: str) -> int:
    record = release(package)
    rel = record["release"]
    variants = rel.get("variants", [])
    artifact = rel.get("artifacts", [{}])[0]

    print(f"{package} {rel['version']}")
    print()
    print("Package")
    print(f"  owner        {record.get('owner','')}")
    print(f"  state        {rel.get('state','')}")
    print(f"  capability   {rel.get('capability','')}")
    print(f"  profile      {rel.get('profile','')}")
    print(f"  semantics    {rel.get('semantic_fingerprint','')}")
    print(f"  review       {rel.get('review',{}).get('state','unknown')}")
    print(f"  safety       {rel.get('safety',{}).get('state','unknown')}")
    print()
    print("Variants")
    for variant in variants:
        target = variant.get("target", {})
        isa = target.get("isa", {})
        req = ", ".join(isa.get("required", []))
        print(
            f"  {variant.get('id','')}  "
            f"{target.get('arch','')}/{target.get('abi','')}  "
            f"{isa.get('baseline','')}  [{req}]"
        )
    print()
    print("Artifact")
    print(f"  sha256       {artifact.get('sha256','')}")
    print(f"  size         {artifact.get('size','')}")
    return 0


def resolve_package(package: str) -> tuple[dict, dict]:
    record = release(package)
    variant, _ = select_variant(record)
    return record, variant


def command_resolve(package: str) -> int:
    record, variant = resolve_package(package)
    rel = record["release"]
    artifact = rel["artifacts"][0]
    target = variant["target"]
    isa = target["isa"]

    print("Resolved remote dependency")
    print()
    print(f"  package      {package}")
    print(f"  release      {rel['version']}")
    print(f"  capability   {rel['capability']}")
    print(f"  profile      {rel['profile']}")
    print(f"  variant      {variant['id']}")
    print(
        "  target       "
        f"{target['arch']} / {target['abi']} / {isa['baseline']}"
    )
    print(f"  requires     {', '.join(isa.get('required', [])) or 'none'}")
    print(f"  artifact     {artifact['sha256']}")
    print("  compatibility yes")
    return 0


def command_add(package: str) -> int:
    record, variant = resolve_package(package)
    rel = record["release"]
    artifact = rel.get("artifacts", [{}])[0]

    digest = artifact.get("sha256")
    semantic = rel.get("semantic_fingerprint")

    if not isinstance(digest, str) or SHA_RE.fullmatch(digest) is None:
        raise RemoteError("active Release Artifact digest is invalid")
    if not isinstance(semantic, str) or SHA_RE.fullmatch(semantic) is None:
        raise RemoteError("active Release semantic fingerprint is invalid")

    review = rel.get("review", {}).get("state", "unknown")
    safety = rel.get("safety", {}).get("state", "unknown")
    provider = record.get("owner")

    values = (
        rel.get("capability"),
        rel.get("profile"),
        provider,
        variant.get("id"),
        review,
        safety,
    )
    if not all(isinstance(x, str) and x for x in values):
        raise RemoteError("active Release resolver metadata is incomplete")

    args = [
        "asmory-add",
        package,
        str(rel["version"]),
        str(rel["capability"]),
        semantic,
        str(rel["profile"]),
        str(provider),
        str(variant["id"]),
        digest,
        str(review),
        str(safety),
    ]

    proc = subprocess.run(args)
    return proc.returncode


def main() -> int:
    parser = argparse.ArgumentParser(prog="asmory-remote")
    sub = parser.add_subparsers(dest="command", required=True)

    search_p = sub.add_parser("search")
    search_p.add_argument("query", nargs="?")

    info_p = sub.add_parser("info")
    info_p.add_argument("package")

    versions_p = sub.add_parser("versions")
    versions_p.add_argument("package")

    resolve_p = sub.add_parser("resolve")
    resolve_p.add_argument("package")

    add_p = sub.add_parser("add")
    add_p.add_argument("package")

    args = parser.parse_args()

    try:
        if args.command == "search":
            return command_search(args.query)
        if args.command == "info":
            return command_info(require_name(args.package))
        if args.command == "versions":
            return command_versions(require_name(args.package))
        if args.command == "resolve":
            return command_resolve(require_name(args.package))
        if args.command == "add":
            return command_add(require_name(args.package))
        raise RemoteError("unknown remote command")
    except RemoteError as exc:
        print(f"remote: {exc}", file=sys.stderr)
        return 27


if __name__ == "__main__":
    raise SystemExit(main())
