#!/usr/bin/env python3
"""Regression checks for the current Charcoal status scope and build profile."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / "charcoal-status").read_text()
PKGBUILD = (ROOT / "PKGBUILD").read_text()
KERNEL_CONFIG = (ROOT / "config-charcoal").read_text()


class CharcoalStatusTests(unittest.TestCase):
    def test_package_series_is_detected_dynamically(self):
        self.assertIn("linux-charcoal-[0-9]+", SCRIPT)
        self.assertIn('KERNEL_SERIES="${CHARCOAL_PACKAGE##*-}"', SCRIPT)
        self.assertNotIn("linux-charcoal-72", SCRIPT)
        self.assertNotIn("linux-neptune-72", SCRIPT)

    def test_running_kernel_is_attributed_to_installed_package(self):
        self.assertIn('pacman -Qqo -- "$RUNNING_MODULE_DIR/pkgbase"', SCRIPT)
        self.assertIn('"$running_owner" == "$CHARCOAL_PACKAGE"', SCRIPT)

    def test_installed_charcoal_config_is_preferred(self):
        self.assertIn('"$CHARCOAL_MODULE_DIR/build/.config"', SCRIPT)
        self.assertIn('BUILD_DIR="$CHARCOAL_MODULE_DIR/build"', SCRIPT)

    def test_compiler_fallback_is_informational(self):
        self.assertIn("Compiler reported by the running kernel", SCRIPT)
        self.assertIn("generated compile.h unavailable", SCRIPT)

    def test_mitigations_off_is_checked_at_runtime(self):
        self.assertIn("grep -qw -- 'mitigations=off' /proc/cmdline", SCRIPT)
        self.assertIn("supported CPU mitigations disabled at runtime", SCRIPT)
        self.assertIn('info "CONFIG_CPU_MITIGATIONS=y:', SCRIPT)

    def test_o2_is_expected_and_o3_is_not_reported_as_a_required_feature(self):
        self.assertIn("config_enabled CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE", SCRIPT)
        self.assertIn("config_disabled CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3", SCRIPT)
        self.assertIn("O2 selected; O3 is disabled as intended", SCRIPT)
        self.assertNotIn('check_config CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3', SCRIPT)
        self.assertIn("'CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y'", PKGBUILD)

    def test_remaining_build_features_are_reported_as_build_configuration(self):
        self.assertIn("build configuration only; not proof of runtime activation", SCRIPT)
        self.assertIn("check_config CONFIG_ZRAM", SCRIPT)
        self.assertIn("check_config CONFIG_X86_AMD_PSTATE", SCRIPT)
        self.assertIn("check_config CONFIG_LTO_CLANG_FULL", SCRIPT)
        self.assertIn("check_config CONFIG_POLLY_CLANG", SCRIPT)

    def test_removed_feature_checks_are_absent(self):
        removed = (
            "CONFIG_SCHED_BORE",
            "CONFIG_SCHED_POC_SELECTOR",
            "CONFIG_LRU_CAST",
            "CONFIG_CPU_IDLE_GOV_NAP",
            "bore_sysctl",
            "sched_policy",
            "scx_lavd",
            "adios",
            "NAP cpuidle",
            "ADIOS I/O scheduler",
            "ZRAM-IR",
        )
        for token in removed:
            with self.subTest(token=token):
                self.assertNotIn(token, SCRIPT)

    def test_zswap_is_disabled_and_zram_is_retained(self):
        self.assertIn("config_disabled CONFIG_ZSWAP", SCRIPT)
        self.assertIn("CONFIG_ZSWAP=n", SCRIPT)
        self.assertIn("# CONFIG_ZSWAP is not set", KERNEL_CONFIG)
        self.assertIn("CONFIG_ZRAM=m", KERNEL_CONFIG)

    def test_amd_pstate_runtime_epp_checks_remain(self):
        self.assertIn("/sys/devices/system/cpu/amd_pstate/status", SCRIPT)
        self.assertIn("energy_performance_preference", SCRIPT)
        self.assertIn("/sys/module/amd_pstate/parameters/epp_boost", SCRIPT)


if __name__ == "__main__":
    unittest.main(verbosity=2)
