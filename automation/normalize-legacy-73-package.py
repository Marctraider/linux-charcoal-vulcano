#!/usr/bin/env python3
"""Correct the r1 kernel package's mkinitcpio identity without rebuilding Linux."""
import gzip
import hashlib
import io
import os
import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

OLD = b"linux-charcoal-73\n"
NEW = b"linux-neptune-73\n"


def main(path):
    package = Path(path)
    if not package.is_file() or package.is_symlink():
        raise SystemExit("normalizer: package is not a regular file")
    with tempfile.TemporaryDirectory(prefix="charcoal-73-normalize-") as tmp:
        raw = Path(tmp) / "input.tar"
        rewritten = Path(tmp) / "output.tar"
        compressed = Path(tmp) / "output.pkg.tar.zst"
        with raw.open("wb") as out:
            subprocess.run(["zstd", "-q", "-d", "-c", "--", str(package)],
                           stdout=out, check=True)
        with tarfile.open(raw, "r:") as src:
            members = src.getmembers()
            names = [m.name for m in members]
            if len(names) != len(set(names)):
                raise SystemExit("normalizer: duplicate package paths")
            info = src.extractfile(".PKGINFO")
            if info is None or b"pkgname = linux-charcoal-73\n" not in info.read():
                raise SystemExit("normalizer: unexpected package identity")
            markers = [m for m in members if m.name.startswith("usr/lib/modules/") and m.name.endswith("/pkgbase")]
            if len(markers) != 1 or ".MTREE" not in names:
                raise SystemExit("normalizer: expected one module pkgbase and .MTREE")
            marker = markers[0]
            current = src.extractfile(marker).read()
            if current == NEW:
                return
            if current != OLD:
                raise SystemExit("normalizer: unsupported existing pkgbase value")
            mtree = gzip.decompress(src.extractfile(".MTREE").read()).decode()
            mtree_path = "./" + marker.name
            lines = mtree.splitlines()
            matches = [i for i, line in enumerate(lines) if line.startswith(mtree_path + " ")]
            if len(matches) != 1:
                raise SystemExit("normalizer: missing or duplicate pkgbase .MTREE record")
            i = matches[0]
            line = lines[i]
            if not re.search(r"\bsize=18\b", line) or not re.search(r"\bsha256digest=[0-9a-f]{64}\b", line):
                raise SystemExit("normalizer: unexpected pkgbase .MTREE format")
            line = re.sub(r"\bsize=18\b", "size=17", line, count=1)
            line = re.sub(r"\bsha256digest=[0-9a-f]{64}\b",
                          "sha256digest=" + hashlib.sha256(NEW).hexdigest(), line, count=1)
            if "md5digest=" in line:
                line = re.sub(r"\bmd5digest=[0-9a-f]{32}\b",
                              "md5digest=" + hashlib.md5(NEW).hexdigest(), line, count=1)
            lines[i] = line
            new_mtree = gzip.compress(("\n".join(lines) + "\n").encode(), mtime=0)
            with tarfile.open(rewritten, "w:", format=tarfile.GNU_FORMAT) as dst:
                for member in members:
                    if member.name == marker.name:
                        member.size = len(NEW)
                        dst.addfile(member, io.BytesIO(NEW))
                    elif member.name == ".MTREE":
                        member.size = len(new_mtree)
                        dst.addfile(member, io.BytesIO(new_mtree))
                    else:
                        stream = src.extractfile(member) if member.isfile() else None
                        dst.addfile(member, stream)
        with compressed.open("wb") as out:
            subprocess.run(["zstd", "-q", "-T0", "-19", "-c", "--", str(rewritten)],
                           stdout=out, check=True)
        check = subprocess.check_output(["zstd", "-q", "-d", "-c", "--", str(compressed)])
        with tarfile.open(fileobj=io.BytesIO(check), mode="r:") as verify:
            if verify.extractfile(marker.name).read() != NEW:
                raise SystemExit("normalizer: rewritten pkgbase did not verify")
            mtree_check = gzip.decompress(verify.extractfile(".MTREE").read()).decode()
            digest = hashlib.sha256(NEW).hexdigest()
            if not any(line.startswith(mtree_path + " ") and "size=17" in line and
                       "sha256digest=" + digest in line for line in mtree_check.splitlines()):
                raise SystemExit("normalizer: rewritten .MTREE did not verify")
        os.chmod(compressed, package.stat().st_mode & 0o777)
        os.replace(compressed, package)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: normalize-legacy-73-package.py PACKAGE")
    main(sys.argv[1])
