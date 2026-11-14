#!/usr/bin/env python3
"""Regression tests for the SteamOS 3.10 / Linux 7.3 source ports."""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ZEN = load_module("port_zen_73", ROOT / "automation/port-zen-cpufreq-7.3.py")

class ZenPortTests(unittest.TestCase):
    def test_removes_only_the_two_reviewed_pstate_selects(self):
        source = (
            "config X86_INTEL_PSTATE\n"
            "\tselect CPU_FREQ_GOV_SCHEDUTIL if SMP\n"
            "\thelp\n"
            "config X86_PCC_CPUFREQ\n"
            "\thelp\n"
            "config X86_AMD_PSTATE\n"
            "\tselect CPU_FREQ_GOV_SCHEDUTIL if SMP\n"
            "\thelp\n"
            "config X86_AMD_PSTATE_DEFAULT_MODE\n"
            "\thelp\n"
        )
        result = ZEN.adapt_source(source)
        self.assertNotIn("\tselect CPU_FREQ_GOV_SCHEDUTIL if SMP\n", result)
        self.assertEqual(result.count("config X86_INTEL_PSTATE"), 1)
        self.assertEqual(result.count("config X86_AMD_PSTATE\n"), 1)

    def test_preserves_already_conditioned_selects(self):
        source = (
            "config X86_INTEL_PSTATE\n"
            "\tselect CPU_FREQ_GOV_SCHEDUTIL if SMP && !ZEN_INTERACTIVE\n"
            "\thelp\n"
            "config X86_AMD_PSTATE\n"
            "\tselect CPU_FREQ_GOV_SCHEDUTIL if SMP && !ZEN_INTERACTIVE\n"
            "\thelp\n"
        )
        self.assertEqual(ZEN.adapt_source(source), source)

    def test_rejects_unreviewed_schedutil_shape(self):
        source = (
            "config X86_INTEL_PSTATE\n"
            "\tselect CPU_FREQ_GOV_SCHEDUTIL\n"
            "\thelp\n"
            "config X86_AMD_PSTATE\n"
            "\tselect CPU_FREQ_GOV_SCHEDUTIL if SMP\n"
            "\thelp\n"
        )
        with self.assertRaises(ZEN.PortError):
            ZEN.adapt_source(source)


if __name__ == "__main__":
    unittest.main()
