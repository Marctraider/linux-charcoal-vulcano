#!/usr/bin/env python3
"""Regression checks for the current Charcoal status utility and package integration."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = ROOT / "charcoal-status"
SCRIPT = SCRIPT_PATH.read_text()
PKGBUILD = (ROOT / "PKGBUILD").read_text()
CONFIG_OVERLAY = (ROOT / "config-charcoal").read_text()


class CharcoalStatusTests(unittest.TestCase):
    def test_script_has_valid_bash_syntax(self):
        subprocess.run(["bash", "-n", str(SCRIPT_PATH)], check=True)

    def test_package_series_is_detected_dynamically(self):
        self.assertIn("linux-charcoal-[0-9]+", SCRIPT)
        self.assertIn('KERNEL_SERIES="${CHARCOAL_PACKAGE##*-}"', SCRIPT)

    def test_running_kernel_is_attributed_to_installed_package(self):
        self.assertIn('pacman -Qqo -- "$RUNNING_MODULE_DIR/pkgbase"', SCRIPT)
        self.assertIn('"$running_owner" == "$CHARCOAL_PACKAGE"', SCRIPT)

    def test_installed_charcoal_config_is_preferred(self):
        self.assertIn('"$CHARCOAL_MODULE_DIR/build/.config"', SCRIPT)
        self.assertIn('BUILD_DIR="$CHARCOAL_MODULE_DIR/build"', SCRIPT)

    def test_compiler_fallback_is_informational(self):
        self.assertIn("Compiler reported by the running kernel", SCRIPT)
        self.assertIn("generated compile.h unavailable", SCRIPT)

    def test_security_and_cpu_target_reporting_remain(self):
        self.assertIn("grep -qw -- 'mitigations=off' /proc/cmdline", SCRIPT)
        self.assertIn("supported CPU mitigations disabled at runtime", SCRIPT)
        self.assertIn('info "CONFIG_CPU_MITIGATIONS=y:', SCRIPT)
        self.assertIn("-march=znver2", SCRIPT)

    def test_current_build_profile_is_reported(self):
        for check in (
            "check_config CONFIG_X86_AMD_PSTATE",
            "check_config CONFIG_LTO_CLANG_FULL",
            "check_config CONFIG_POLLY_CLANG",
            "config_enabled CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE",
            "config_disabled CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3",
        ):
            with self.subTest(check=check):
                self.assertIn(check, SCRIPT)
        self.assertIn("CONFIG_X86_AMD_PSTATE=y", CONFIG_OVERLAY)
        self.assertIn("CONFIG_LTO_CLANG_FULL=y", CONFIG_OVERLAY)
        self.assertIn("CONFIG_POLLY_CLANG=y", CONFIG_OVERLAY)
        self.assertIn("CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y", CONFIG_OVERLAY)


    def test_zram_detection_is_removed(self):
        self.assertNotIn("CONFIG_ZRAM", SCRIPT)
        self.assertNotIn("/sys/module/zram", SCRIPT)
        self.assertNotIn("/sys/block/zram", SCRIPT)

    def test_lavd_runtime_and_performance_mode_are_checked(self):
        self.assertIn('systemctl is-active --quiet "$LAVD_SERVICE"', SCRIPT)
        self.assertIn('systemctl show --property=MainPID --value "$LAVD_SERVICE"', SCRIPT)
        self.assertIn('"/proc/$LAVD_PID/cmdline"', SCRIPT)
        self.assertIn('" --performance "', SCRIPT)
        self.assertIn('/sys/kernel/sched_ext/root/ops', SCRIPT)
        self.assertIn('active scheduler: $SCHED_EXT_OPS', SCRIPT)

    def test_status_utility_is_installed_in_kernel_package(self):
        self.assertIn('install -Dm755 "$startdir/charcoal-status" "$pkgdir/usr/bin/charcoal-status"', PKGBUILD)
        self.assertIn("sudo charcoal-status", (ROOT / "README.md").read_text())

    def test_amd_pstate_epp_reporting_remains(self):
        self.assertIn("/sys/devices/system/cpu/amd_pstate/status", SCRIPT)
        self.assertIn("energy_performance_preference", SCRIPT)
        self.assertIn("/sys/module/amd_pstate/parameters/epp_boost", SCRIPT)


if __name__ == "__main__":
    unittest.main(verbosity=2)
