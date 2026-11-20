#!/usr/bin/env python3
"""Ensure the legacy BORE overlay is retained only as a reference, not built."""
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
recipe = (root / "PKGBUILD").read_text()

# This Charcoal 7.3 profile deliberately excludes BORE. Keep the historical
# patch available for reference, but never add it to the active kernel recipe.
for target in ("latest-bore.patch", "latest-bore-sched-ext-coexistence-fix.patch"):
    assert target not in recipe, f"excluded BORE patch unexpectedly enabled: {target}"

reference = root / "6.16.12-bore-6.8.0-final.patch"
subprocess.run(
    ["git", "apply", "--numstat", str(reference)],
    cwd=root,
    check=True,
    capture_output=True,
)
print("BORE is excluded from the active Charcoal 7.3 recipe; reference patch syntax passed")
