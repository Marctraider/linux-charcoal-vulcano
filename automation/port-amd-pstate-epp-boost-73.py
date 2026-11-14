#!/usr/bin/env python3
"""Port the pinned AMD P-State EPP boost core patch to Valve Linux 7.3."""
from __future__ import annotations

import argparse
import re
import subprocess
import tempfile
from pathlib import Path

HUNKS_TO_REBASE = {
    "drivers/cpufreq/amd-pstate.h": "@@ -10,6 +10,7 @@",
    "drivers/cpufreq/amd-pstate.c": "@@ -27,6 +27,7 @@",
}
HEADER_INCLUDE = "#include <linux/sched/cpufreq.h>\n"
CPU_INCLUDE = "#include <linux/cpu.h>\n"


class PortError(RuntimeError):
    pass


def remove_reviewed_include_hunk(patch: str, relative_path: str, header: str) -> str:
    sections = re.split(r"(?=^diff --git )", patch, flags=re.M)
    found = 0
    for index, section in enumerate(sections):
        if not section.startswith(f"diff --git a/{relative_path} b/{relative_path}\n"):
            continue
        pattern = re.compile(
            r"(?ms)^" + re.escape(header) + r".*?(?=^@@ |\Z)"
        )
        sections[index], count = pattern.subn("", section, count=1)
        if count != 1:
            raise PortError(f"expected one reviewed include hunk in {relative_path}")
        found += 1
    if found != 1:
        raise PortError(f"expected one diff section for {relative_path}, found {found}")
    return "".join(sections)


def ensure_include(path: Path, include: str, anchor: str) -> None:
    text = path.read_text(encoding="utf-8")
    if include in text:
        return
    if text.count(anchor) != 1:
        raise PortError(f"cannot uniquely place {include.strip()} in {path}")
    path.write_text(text.replace(anchor, anchor + include, 1), encoding="utf-8")


def apply_port(patch_path: Path, tree: Path) -> None:
    source = (tree / "drivers/cpufreq/amd-pstate.c").read_text(encoding="utf-8")
    header = (tree / "drivers/cpufreq/amd-pstate.h").read_text(encoding="utf-8")
    if "module_param_cb(epp_boost" in source:
        raise PortError("EPP boost code is already present; refusing duplicate application")
    patch = patch_path.read_text(encoding="utf-8")
    for relative_path, hunk in HUNKS_TO_REBASE.items():
        patch = remove_reviewed_include_hunk(patch, relative_path, hunk)

    with tempfile.TemporaryDirectory(prefix="charcoal-epp-73-") as temp:
        adapted = Path(temp) / "amd-pstate-epp-boost-73.patch"
        adapted.write_text(patch, encoding="utf-8")
        check = subprocess.run(
            ["git", "-C", str(tree), "apply", "--check", "--whitespace=nowarn", str(adapted)],
            text=True, capture_output=True,
        )
        if check.returncode:
            raise PortError("rebased EPP core patch does not apply cleanly:\n" + check.stderr)
        apply = subprocess.run(
            ["git", "-C", str(tree), "apply", "--whitespace=nowarn", str(adapted)],
            text=True, capture_output=True,
        )
        if apply.returncode:
            raise PortError("rebased EPP core patch failed after check:\n" + apply.stderr)

    ensure_include(
        tree / "drivers/cpufreq/amd-pstate.h",
        HEADER_INCLUDE,
        "#include <linux/platform_profile.h>\n",
    )
    ensure_include(
        tree / "drivers/cpufreq/amd-pstate.c",
        CPU_INCLUDE,
        "#include <linux/smp.h>\n",
    )

    source = (tree / "drivers/cpufreq/amd-pstate.c").read_text(encoding="utf-8")
    header = (tree / "drivers/cpufreq/amd-pstate.h").read_text(encoding="utf-8")
    required_source = (
        "static void amd_pstate_epp_boost_update_util",
        "static void amd_pstate_epp_boost_enable",
        "static void amd_pstate_epp_boost_disable",
        "module_param_cb(epp_boost",
        "amd_pstate_epp_boost_enable(policy);",
        "amd_pstate_epp_boost_disable(policy);",
    )
    for marker in required_source:
        if marker not in source:
            raise PortError(f"ported amd-pstate.c is missing {marker!r}")
    required_fields = (
        "epp_boost_update_util",
        "epp_boost_last_sample",
        "epp_boost_last_busy",
        "epp_boost_active",
        "epp_boost_registered",
    )
    for marker in required_fields:
        if marker not in header:
            raise PortError(f"ported amd-pstate.h is missing {marker!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("patch", type=Path)
    parser.add_argument("tree", type=Path)
    args = parser.parse_args()
    try:
        apply_port(args.patch, args.tree)
    except (OSError, UnicodeDecodeError, PortError) as exc:
        raise SystemExit(f"AMD P-State EPP boost 7.3 port failed: {exc}") from exc
    print("AMD P-State EPP boost 7.3 port applied and required symbols verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
