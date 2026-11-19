#!/usr/bin/env python3
"""Validate the requested Linux 7.3 performance and sched_ext configuration."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PKGBUILD = (ROOT / "PKGBUILD").read_text()
CONFIG = (ROOT / "config-charcoal").read_text()


class KernelConfigValidationTests(unittest.TestCase):
    def test_o2_zen2_and_clang_optimizations(self):
        self.assertIn("-march=znver2", PKGBUILD)
        self.assertIn("CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y", CONFIG)
        self.assertIn("# CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3 is not set", CONFIG)
        self.assertIn("CONFIG_LTO_CLANG_FULL=y", CONFIG)
        self.assertIn("CONFIG_POLLY_CLANG=y", CONFIG)

    def test_requested_boot_parameters_are_enabled(self):
        self.assertIn('CONFIG_CMDLINE="amd_pstate.epp_boost=1 mitigations=off"', CONFIG)
        self.assertIn("CONFIG_X86_AMD_PSTATE_DEFAULT_MODE=3", CONFIG)
        self.assertIn("CONFIG_CPU_MITIGATIONS=y", CONFIG)

    def test_lavd_kernel_prerequisites_and_bore_fallback(self):
        for setting in (
            "CONFIG_SCHED_CLASS_EXT=y",
            "CONFIG_SCHED_BORE=y",
            "CONFIG_BPF=y",
            "CONFIG_BPF_SYSCALL=y",
            "CONFIG_BPF_JIT=y",
            "CONFIG_BPF_JIT_ALWAYS_ON=y",
            "CONFIG_BPF_JIT_DEFAULT_ON=y",
            "CONFIG_DEBUG_INFO_DWARF5=y",
            "CONFIG_DEBUG_INFO_BTF=y",
            "CONFIG_TRACEPOINTS=y",
            "CONFIG_FTRACE=y",
            "CONFIG_FTRACE_SYSCALLS=y",
        ):
            self.assertIn(setting, CONFIG)
            self.assertIn(f"'{setting}'", PKGBUILD)

    def test_debug_instrumentation_is_disabled_but_btf_is_retained(self):
        for setting in (
            "CONFIG_SCHED_DEBUG=n",
            "CONFIG_FUNCTION_TRACER=n",
            "CONFIG_FUNCTION_GRAPH_TRACER=n",
            "CONFIG_LOCKDEP=n",
            "CONFIG_PROVE_LOCKING=n",
            "CONFIG_KASAN=n",
            "CONFIG_KCSAN=n",
            "CONFIG_KFENCE=n",
            "CONFIG_KMSAN=n",
            "CONFIG_UBSAN=n",
        ):
            self.assertIn(setting, CONFIG)
        self.assertIn("CONFIG_FTRACE=y", CONFIG)
        self.assertIn("CONFIG_FTRACE_SYSCALLS=y", CONFIG)
        self.assertIn("# CONFIG_DEBUG_INFO_BTF_MODULES is not set", CONFIG)
        self.assertNotIn("CONFIG_DEBUG_INFO_NONE=y", CONFIG)
        self.assertNotIn("CONFIG_DEBUG_INFO_REDUCED=y", CONFIG)
        self.assertNotIn("CONFIG_DEBUG_INFO_SPLIT=y", CONFIG)

    def test_unrequested_patch_series_are_not_in_build_recipe(self):
        source_block = PKGBUILD.split("source=(", 1)[1].split(")", 1)[0]
        for name in (
            "latest-lru_cast.patch",
            "latest-zram-ir.patch",
            "latest-o3.patch",
            "latest-poc-selector.patch",
            "latest-adios.patch",
            "latest-zen-01.patch",
            "nap-6.12-v0.6.5.patch",
            "drm_sched_rr_default.patch",
        ):
            self.assertNotIn(name, source_block)


if __name__ == "__main__":
    unittest.main()
