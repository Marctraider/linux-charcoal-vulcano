#!/usr/bin/env python3
"""Apply the reviewed Van Gogh 50 W PPT limit port to Valve Linux 7.3."""
from __future__ import annotations

import argparse
from pathlib import Path

OLD_MAX = "*max_power_limit = 29;"
NEW_MAX = "*max_power_limit = 50;"
OLD_FAST = "power_context->max_fast_ppt_limit = 30;"
NEW_FAST = "power_context->max_fast_ppt_limit = 51;"


class PortError(RuntimeError):
    pass


def occurrences(text: str, token: str) -> int:
    return text.count(token)


def candidate_lines(text: str) -> str:
    return "\n".join(
        f"{number}: {line}"
        for number, line in enumerate(text.splitlines(), 1)
        if "max_power_limit" in line or "max_fast_ppt_limit" in line
    )


def port(text: str) -> tuple[str, bool]:
    old_max = occurrences(text, OLD_MAX)
    new_max = occurrences(text, NEW_MAX)
    old_fast = occurrences(text, OLD_FAST)
    new_fast = occurrences(text, NEW_FAST)

    if old_max == 1 and new_max == 0 and old_fast == 1 and new_fast == 0:
        return (
            text.replace(OLD_MAX, NEW_MAX, 1).replace(OLD_FAST, NEW_FAST, 1),
            True,
        )
    if old_max == 0 and new_max == 1 and old_fast == 0 and new_fast == 1:
        return text, False

    raise PortError(
        "Valve 7.3 Van Gogh power-limit anchors changed; refusing a blind edit. "
        f"max old/new={old_max}/{new_max}, fast old/new={old_fast}/{new_fast}. "
        "Current candidates:\n" + candidate_lines(text)
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    try:
        text = args.source.read_text(encoding="utf-8")
        updated, changed = port(text)
    except (OSError, UnicodeDecodeError, PortError) as exc:
        raise SystemExit(f"Van Gogh power-limit 7.3 port failed: {exc}") from exc
    if changed:
        args.source.write_text(updated, encoding="utf-8")
    print(f"Van Gogh 50 W / 51 W power-limit port changed={changed}")
    print(candidate_lines(updated))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
