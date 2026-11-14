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
VANGOGH = load_module("port_vangogh_power_73", ROOT / "automation/port-vangogh-power-7.3.py")


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


class VanGoghPortTests(unittest.TestCase):
    def test_raises_both_reviewed_limits(self):
        source = (
            "static int get_power_limit(void) {\n"
            "\t*max_power_limit = 29;\n"
            "\tpower_context->max_fast_ppt_limit = 30;\n"
            "}\n"
        )
        result, changed = VANGOGH.port(source)
        self.assertTrue(changed)
        self.assertIn("*max_power_limit = 50;", result)
        self.assertIn("max_fast_ppt_limit = 51;", result)

    def test_is_idempotent(self):
        source = (
            "*max_power_limit = 50;\n"
            "power_context->max_fast_ppt_limit = 51;\n"
        )
        result, changed = VANGOGH.port(source)
        self.assertFalse(changed)
        self.assertEqual(result, source)

    def test_rejects_unreviewed_values(self):
        source = (
            "*max_power_limit = 35;\n"
            "power_context->max_fast_ppt_limit = 36;\n"
        )
        with self.assertRaises(VANGOGH.PortError):
            VANGOGH.port(source)


if __name__ == "__main__":
    unittest.main()
