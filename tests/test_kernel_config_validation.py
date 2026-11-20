#!/usr/bin/env python3
"""Validate the requested Linux 7.3 performance and sched_ext configuration."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PKGBUILD = (ROOT / "PKGBUILD").read_text()
CONFIG = (ROOT / "config-charcoal").read_text()


class KernelConfigValidationTests(unittest.TestCase):
    def test_o2_zen2_and_clang_optimizations(self):
        self.assertIn("polly", PKGBUILD.split("makedepends=(", 1)[1].split(")", 1)[0])
        self.assertIn("CONFIG_POLLY_CLANG", PKGBUILD)
        polly_patch = (ROOT / "7.2-clang-polly-from-cachyos-7.1.patch").read_text()
        self.assertIn("LLVMPolly.so", polly_patch)
        self.assertIn("-mllvm -polly", polly_patch)
        self.assertIn("-march=znver2 -mtune=znver2", PKGBUILD)
        guard = (ROOT / "zen2-compile-check.h").read_text()
        self.assertIn("__znver2", guard)
        self.assertIn("__tune_znver2__", guard)
        self.assertIn("_verify_zen2_compiler_target", PKGBUILD)
        self.assertIn("_verify_zen2_compiler_target\\n", PKGBUILD)
        self.assertIn("scripts/config --enable CC_OPTIMIZE_FOR_PERFORMANCE", PKGBUILD)
        self.assertIn("scripts/config --disable CC_OPTIMIZE_FOR_PERFORMANCE_O3", PKGBUILD)
        self.assertIn("_make_llvm olddefconfig\\n  _validate_kernel_config", PKGBUILD)
        self.assertIn("KBUILD_BUILD_USER=${pkgbase}-znver2", PKGBUILD)
        self.assertIn("# CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3 is not set", PKGBUILD)
        self.assertIn("CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y", CONFIG)
        self.assertIn("CONFIG_LTO_CLANG_FULL=y", CONFIG)
        self.assertIn("CONFIG_POLLY_CLANG=y", CONFIG)

    def test_requested_boot_parameters_are_enabled(self):
        self.assertIn('CONFIG_CMDLINE="amd_pstate.epp_boost=1 mitigations=off"', CONFIG)
        self.assertIn("CONFIG_X86_AMD_PSTATE_DEFAULT_MODE=3", CONFIG)
        self.assertIn("CONFIG_CPU_MITIGATIONS=y", CONFIG)

    def test_lavd_kernel_prerequisites(self):
        for setting in (
            "CONFIG_SCHED_CLASS_EXT=y",
            "CONFIG_BPF=y",
            "CONFIG_BPF_SYSCALL=y",
            "CONFIG_PERF_EVENTS=y",
            "CONFIG_UPROBES=y",
            "CONFIG_UPROBE_EVENTS=y",
            "CONFIG_BPF_EVENTS=y",
            "CONFIG_BPF_JIT=y",
            "CONFIG_BPF_JIT_ALWAYS_ON=y",
            "CONFIG_BPF_JIT_DEFAULT_ON=y",
            "CONFIG_DEBUG_INFO_DWARF5=y",
            "CONFIG_DEBUG_INFO_BTF=y",
            "CONFIG_TRACEPOINTS=y",
            "CONFIG_FTRACE=y",
            "CONFIG_FTRACE_SYSCALLS=y",
            "CONFIG_FUNCTION_TRACER=y",
            "CONFIG_DYNAMIC_FTRACE=y",
        ):
            self.assertIn(setting, CONFIG)
            self.assertIn(f"'{setting}'", PKGBUILD)

    def test_debug_instrumentation_is_disabled_but_btf_is_retained(self):
        for setting in (
            "# CONFIG_STACK_TRACER is not set",
            "# CONFIG_FPROBE is not set",
            "# CONFIG_FUNCTION_GRAPH_TRACER is not set",
            "# CONFIG_LOCKDEP is not set",
            "# CONFIG_PROVE_LOCKING is not set",
            "# CONFIG_KASAN is not set",
            "# CONFIG_KCSAN is not set",
            "# CONFIG_KFENCE is not set",
            "# CONFIG_KMSAN is not set",
            "# CONFIG_UBSAN is not set",
            "# CONFIG_KPROBES is not set",
            "# CONFIG_PROFILING is not set",
            "# CONFIG_DEBUG_ATOMIC_SLEEP is not set",
            "# CONFIG_DEBUG_MUTEXES is not set",
            "# CONFIG_DEBUG_SPINLOCK is not set",
            "# CONFIG_DEBUG_LIST is not set",
            "# CONFIG_DEBUG_OBJECTS is not set",
            "# CONFIG_DEBUG_PAGEALLOC is not set",
            "# CONFIG_PAGE_POISONING is not set",
        ):
            self.assertIn(setting, CONFIG)
        self.assertIn("CONFIG_FTRACE=y", CONFIG)
        self.assertIn("# CONFIG_STACK_TRACER is not set", CONFIG)
        self.assertIn("'# CONFIG_STACK_TRACER is not set'", PKGBUILD)
        self.assertIn("CONFIG_FTRACE_SYSCALLS=y", CONFIG)
        self.assertIn("scripts/config --enable DYNAMIC_FTRACE", PKGBUILD)
        self.assertIn("scripts/config --enable FUNCTION_TRACER", PKGBUILD)
        self.assertIn("scripts/config --disable FUNCTION_GRAPH_TRACER", PKGBUILD)
        self.assertIn("scripts/config --disable FPROBE", PKGBUILD)
        self.assertIn("scripts/config --disable STACK_TRACER", PKGBUILD)
        self.assertIn("scripts/config --disable PROVE_LOCKING", PKGBUILD)
        self.assertIn("scripts/config --disable LOCKDEP", PKGBUILD)
        self.assertNotIn("'CONFIG_NTSYNC=y'", PKGBUILD)
        self.assertIn("# CONFIG_DEBUG_INFO_BTF_MODULES is not set", CONFIG)
        self.assertNotIn("CONFIG_DEBUG_INFO_NONE=y", CONFIG)
        self.assertNotIn("CONFIG_DEBUG_INFO_REDUCED=y", CONFIG)
        self.assertNotIn("CONFIG_DEBUG_INFO_SPLIT=y", CONFIG)

    def test_build_generates_kernel_specific_btf_header_for_core(self):
        self.assertIn("_make_llvm -C tools/bpf/bpftool", PKGBUILD)
        self.assertIn(
            "tools/bpf/bpftool/bpftool btf dump file vmlinux format c",
            PKGBUILD,
        )
        self.assertIn("test -s tools/bpf/bpftool/vmlinux.h", PKGBUILD)
        self.assertNotIn("vmlinux.h feature-clang-bpf-co-re=1", PKGBUILD)

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


    def test_current_patch_inputs_and_removed_features(self):
        source_block = PKGBUILD.split("source=(", 1)[1].split(")", 1)[0]
        for patch in (
            "vangogh_allow_higher_cpu_freq.patch",
            "latest-amd-pstate-epp-02-cache-order.patch",
            "latest-amd-pstate-epp-03-core.patch",
            "latest-clang-polly.patch",
        ):
            self.assertIn(patch, source_block)
        for excluded in (
            "nap-6.12-v0.6.5.patch",
            "latest-bore.patch",
            "drm_sched_rr_default.patch",
            "latest-lru_cast.patch",
            "latest-zram-ir.patch",
            "latest-poc-selector.patch",
            "latest-adios.patch",
        ):
            self.assertNotIn(excluded, source_block)
        prepare_sources = (ROOT / "automation/prepare-sources-73.py").read_text()
        self.assertNotIn('"bore": "latest-bore.patch"', prepare_sources)


if __name__ == "__main__":
    unittest.main()
