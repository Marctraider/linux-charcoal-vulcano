#!/usr/bin/env python3
"""Port the pinned Zen schedutil-dependency change to Valve's Linux 7.3 Kconfig."""
from __future__ import annotations

import argparse
import re
from pathlib import Path

DIFF_HEADER = "diff --git a/drivers/cpufreq/Kconfig.x86 b/drivers/cpufreq/Kconfig.x86"
REMOVED = "-\tselect CPU_FREQ_GOV_SCHEDUTIL if SMP"
TARGET = "\tselect CPU_FREQ_GOV_SCHEDUTIL if SMP\n"
PSTATE_SELECT = "\tselect CPU_FREQ_GOV_SCHEDUTIL if SMP && !ZEN_INTERACTIVE\n"
CONFIGS = ("X86_INTEL_PSTATE", "X86_AMD_PSTATE")


class PortError(RuntimeError):
    pass


def validate_patch(patch: str) -> None:
    if DIFF_HEADER not in patch:
        raise PortError("pinned Zen patch no longer targets drivers/cpufreq/Kconfig.x86")
    if patch.count(REMOVED) != 2:
        raise PortError("pinned Zen patch no longer removes exactly two schedutil selects")
    for config in CONFIGS:
        if f"config {config}" not in patch:
            raise PortError(f"pinned Zen patch no longer contains {config}")


def config_bounds(source: str, config: str) -> tuple[int, int]:
    pattern = re.compile(rf"^config {config}\n.*?(?=^config |\Z)", re.M | re.S)
    matches = list(pattern.finditer(source))
    if len(matches) != 1:
        raise PortError(f"expected one Valve 7.3 {config} block, found {len(matches)}")
    return matches[0].start(), matches[0].end()


def adapt_source(source: str) -> str:
    updated = source
    for config in CONFIGS:
        start, end = config_bounds(updated, config)
        block = updated[start:end]
        if PSTATE_SELECT in block:
            continue
        count = block.count(TARGET)
        if count == 1:
            block = block.replace(TARGET, "", 1)
        elif count == 0 and "select CPU_FREQ_GOV_SCHEDUTIL" not in block:
            pass
        else:
            raise PortError(
                f"unexpected schedutil dependency in {config}: "
                f"unconditional_count={count}"
            )
        updated = updated[:start] + block + updated[end:]
    return updated


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("patch", type=Path)
    parser.add_argument("target", type=Path)
    args = parser.parse_args()
    try:
        patch = args.patch.read_text(encoding="utf-8")
        source = args.target.read_text(encoding="utf-8")
        validate_patch(patch)
        adapted = adapt_source(source)
    except (OSError, UnicodeDecodeError, PortError) as exc:
        raise SystemExit(f"Zen cpufreq 7.3 port failed: {exc}") from exc
    args.target.write_text(adapted, encoding="utf-8")
    print(
        "Applied explicit Zen schedutil dependency port for Valve 7.3: "
        "removed unconditional selects from Intel/AMD P-State"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
