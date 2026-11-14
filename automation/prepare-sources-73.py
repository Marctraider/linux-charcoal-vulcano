#!/usr/bin/env python3
"""Fetch and verify the pinned Valve 7.3 source archive and patch inputs."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

ARCHIVE_URL = (
    "https://steamdeck-packages.steamos.cloud/archlinux-mirror/sources/"
    "jupiter-3.10/linux-neptune-73-7.3.1.valve2-1.src.tar.gz"
)
ARCHIVE_SHA256 = "a6316acc22954d0685ac923248995246789a1f3b5ee6890d378ce2c3efa25af8"
OUTPUTS = {
    "vangogh_freq_4_2ghz": "vangogh_allow_higher_cpu_freq.patch",
    "lru_cast": "latest-lru_cast.patch",
    "zram_ir": "latest-zram-ir.patch",
    "amd_pstate_epp_02_cache_order": "latest-amd-pstate-epp-02-cache-order.patch",
    "amd_pstate_epp_03_core": "latest-amd-pstate-epp-03-core.patch",
    "o3_7_3": "latest-o3.patch",
    "clang_polly_7_2_port": "latest-clang-polly.patch",
    "bore": "latest-bore.patch",
    "poc_selector": "latest-poc-selector.patch",
    "adios": "latest-adios.patch",
    "adios_default": "latest-adios-default.patch",
    "zen_evdev_call_rcu": "latest-zen-01.patch",
    "zen_pstate_schedutil_dependency": "latest-zen-02.patch",
    "zstd_crypto_default_level_1": "zstd-crypto-default-level-1.patch",
}
LOCAL_OVERRIDES = {
    "clang_polly_7_2_port": "7.2-clang-polly-from-cachyos-7.1.patch",
}


class OpenwallPre(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.depth = 0
        self.started = False
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "pre" and not self.started:
            self.started = True
            self.depth = 1
        elif tag == "pre" and self.depth:
            self.depth += 1

    def handle_endtag(self, tag: str) -> None:
        if tag == "pre" and self.depth:
            self.depth -= 1

    def handle_data(self, data: str) -> None:
        if self.depth:
            self.parts.append(data)


def download(url: str, destination: Path) -> None:
    request = urllib.request.Request(
        url, headers={"User-Agent": "Charcoal-SteamOS-7.3-build/1.0"}
    )
    with urllib.request.urlopen(request, timeout=240) as response, destination.open("wb") as out:
        shutil.copyfileobj(response, out, length=1024 * 1024)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git_blob(path: Path) -> str:
    data = path.read_bytes()
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def openwall_patch(url: str, destination: Path) -> None:
    html_file = destination.with_suffix(destination.suffix + ".html")
    download(url, html_file)
    parser = OpenwallPre()
    parser.feed(html_file.read_text(encoding="utf-8", errors="replace"))
    html_file.unlink()
    if not parser.started:
        raise RuntimeError(f"mailing-list archive has no preformatted patch: {url}")
    # Openwall indents the entire preformatted message by four display columns.
    lines = []
    for line in "".join(parser.parts).replace("\r", "").splitlines():
        lines.append(line[4:] if line.startswith("    ") else line)
    patch = "\n".join(lines) + "\n"
    if "diff --git " not in patch:
        raise RuntimeError(f"mailing-list archive did not contain a git patch: {url}")
    destination.write_text(patch, encoding="utf-8")


def source_url(item: dict[str, str]) -> str:
    if item.get("url"):
        return item["url"]
    return (
        "https://raw.githubusercontent.com/"
        + item["repository"] + "/" + item["commit"] + "/" + item["path"]
    )


def prepare(root: Path) -> None:
    archive = root / "valve-source.tar.gz"
    if not archive.is_file() or sha256(archive) != ARCHIVE_SHA256:
        print("Downloading exact Valve 7.3.1.valve2-1 source archive...")
        archive.unlink(missing_ok=True)
        download(ARCHIVE_URL, archive)
    actual_archive_sha = sha256(archive)
    if actual_archive_sha != ARCHIVE_SHA256:
        raise RuntimeError(
            f"Valve source archive SHA-256 mismatch: expected {ARCHIVE_SHA256}, "
            f"got {actual_archive_sha}"
        )
    print(f"Valve source archive verified: sha256={actual_archive_sha}")

    manifest_path = root / "automation/patch-candidates-7.3.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    completed = []
    for item in manifest["patches"]:
        name = item["name"]
        output_name = OUTPUTS.get(name)
        if not output_name:
            continue
        destination = root / output_name
        local = LOCAL_OVERRIDES.get(name) or item.get("local_path")
        if local:
            source = root / local
            if not source.is_file():
                raise RuntimeError(f"missing pinned local patch {local}")
            if source.resolve() != destination.resolve():
                shutil.copyfile(source, destination)
        elif item.get("format") == "openwall-pre":
            openwall_patch(source_url(item), destination)
        else:
            download(source_url(item), destination)

        expected_blob = item.get("blob")
        if expected_blob:
            actual_blob = git_blob(destination)
            if actual_blob != expected_blob:
                raise RuntimeError(
                    f"{name} Git blob mismatch: expected {expected_blob}, got {actual_blob}"
                )
        expected_commit = item.get("expected_commit")
        if expected_commit:
            first = destination.read_text(encoding="utf-8", errors="replace").splitlines()[0]
            if not first.startswith(f"From {expected_commit} "):
                raise RuntimeError(f"{name} patch commit header does not match {expected_commit}")
        completed.append((name, destination.name, sha256(destination)))
    print("Prepared pinned patch inputs:")
    for name, filename, digest in completed:
        print(f"{name}\t{filename}\tsha256={digest}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    try:
        prepare(args.root.resolve())
    except (OSError, ValueError, KeyError, urllib.error.URLError, RuntimeError) as exc:
        print(f"Linux 7.3 source preparation failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
