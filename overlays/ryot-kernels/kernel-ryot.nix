# Desktop/Gaming kernel - optimized for interactive workloads
#
# Best for:
# - Gaming desktops and workstations
# - Development machines requiring responsiveness
# - Systems with modern CPUs (Zen3+, Intel 10th gen+)
#
# Key characteristics:
# - Low latency (1000Hz timer, full preemption)
# - BORE scheduler for interactive responsiveness
# - ThinLTO for performance with reasonable build times
# - x86_64-v3 targeting (requires AVX2 support)
{
  lib,
  final,
  inputs,
  helpers,
  cachyosKernels,
}:
let
  baseKernel = cachyosKernels.linux-cachyos-latest;

  kernel = baseKernel.override {
    pname = "linux-ryot";

    # Compiler & Optimization
    lto = "thin"; # ThinLTO - balances build time and performance
    processorOpt = "x86_64-v3"; # AVX2 optimizations for modern CPUs
    ccHarder = true; # Enable -O3 optimizations

    # Scheduler & Responsiveness
    cpusched = "bore"; # Optimal for interactive/gaming workloads
    hzTicks = "1000"; # 1ms timer resolution for lowest latency
    tickrate = "full"; # Full dynamic ticks
    preemptType = "full"; # Maximum desktop responsiveness

    # Network
    bbr3 = true; # Modern TCP congestion control

    # Memory
    hugepage = "always"; # Benefits gaming and large applications

    # Security/Features - prioritize performance
    kcfi = false;
    hardened = false;
    handheld = false;
    rt = false;
    acpiCall = false;

    # Defaults
    performanceGovernor = false; # Allow user-controlled power management
    autoModules = true;
  };

  # Apply LLVM fixes for out-of-tree modules (nvidia, etc.)
  packages = helpers.kernelModuleLLVMOverride (final.linuxKernel.packagesFor kernel);
in
{
  inherit kernel packages;
}
