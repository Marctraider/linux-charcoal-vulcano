#!/usr/bin/env python3
"""Regression checks for the Charcoal status script's series and optional-feature handling."""
from pathlib import Path
import re
import unittest

SCRIPT = (Path(__file__).resolve().parents[1] / "charcoal-status").read_text()


class CharcoalStatusTests(unittest.TestCase):
    def test_package_series_is_detected_dynamically(self):
        self.assertIn("linux-charcoal-[0-9]+", SCRIPT)
        self.assertIn('KERNEL_SERIES="${CHARCOAL_PACKAGE##*-}"', SCRIPT)
        self.assertNotIn("linux-charcoal-72", SCRIPT)
        self.assertNotIn("linux-neptune-72", SCRIPT)

    def test_running_kernel_uses_pkgbase_and_pacman_owner(self):
        self.assertIn('running_pkgbase=$(<"$RUNNING_MODULE_DIR/pkgbase")', SCRIPT)
        self.assertIn('pacman -Qqo -- "$RUNNING_MODULE_DIR/pkgbase"', SCRIPT)
        self.assertIn('"$running_owner" == "$CHARCOAL_PACKAGE"', SCRIPT)

    def test_installed_config_is_selected_from_charcoal_module_tree(self):
        self.assertIn('"$CHARCOAL_MODULE_DIR/build/.config"', SCRIPT)
        self.assertIn('BUILD_DIR="$CHARCOAL_MODULE_DIR/build"', SCRIPT)

    def test_nap_disabled_is_informational_not_a_failure(self):
        nap_section = SCRIPT.split('section "NAP cpuidle governor"', 1)[1].split('section "ADIOS I/O scheduler"', 1)[0]
        self.assertIn('info "NAP cpuidle governor is disabled in this build', nap_section)
        self.assertIn('info "NAP is not exposed by the running kernel', nap_section)
        self.assertNotIn('fail "NAP', nap_section)

    def test_generic_cpu_absence_is_not_a_warning(self):
        self.assertIn("not treating CONFIG_GENERIC_CPU absence as a failure", SCRIPT)
        self.assertNotRegex(SCRIPT, r'warn .*CONFIG_GENERIC_CPU')

    def test_compiler_fallback_is_informational(self):
        self.assertIn("Compiler reported by the running kernel", SCRIPT)
        self.assertIn("generated compile.h unavailable", SCRIPT)

    def test_scheduler_patterns_match_bracketed_active_values(self):
        self.assertIn("grep -q '\\[adios\\]'", SCRIPT)
        self.assertIn("grep -q '\\[lz4\\]'", SCRIPT)

    def test_mitigations_check_distinguishes_build_config_from_boot_argument(self):
        self.assertIn("mitigations=off is a runtime control", SCRIPT)
        self.assertIn("compiled in (CONFIG_CPU_MITIGATIONS=y)", SCRIPT)


if __name__ == "__main__":
    unittest.main(verbosity=2)
