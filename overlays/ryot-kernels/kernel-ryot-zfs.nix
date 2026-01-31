# ZFS-compatible server kernel
#
# Best for:
# - Servers and NAS systems using ZFS
# - Containerized workloads (Docker, Podman)
# - Mixed server workloads requiring responsiveness
#
# Key characteristics:
# - ZFS compatibility via CachyOS-patched zfs module
# - Balanced latency (500Hz timer)
# - ThinLTO for performance
# - Full preemption for container responsiveness
#
# IMPORTANT: Use zfs_cachyos module for kernel compatibility:
#   boot.zfs.package = config.boot.kernelPackages.zfs_cachyos;
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
    pname = "linux-ryot-zfs";

    # Compiler & Optimization
    lto = "thin";
    processorOpt = "x86_64-v3"; # Modern server CPUs (Zen2+, Intel 10th gen+)
    ccHarder = true;

    # Scheduler & Responsiveness (server-balanced)
    cpusched = "bore"; # Good for mixed workloads
    hzTicks = "500"; # Balanced interrupt overhead
    tickrate = "full";
    preemptType = "full"; # Responsive for containers

    # Network
    bbr3 = true; # Better throughput for NFS/network services

    # Memory
    hugepage = "always"; # Benefits ZFS ARC and containers

    # Defaults
    kcfi = false;
    hardened = false;
    handheld = false;
    rt = false;
    acpiCall = false;
    performanceGovernor = false;
    autoModules = true;
  };

  # Apply LLVM fixes and include CachyOS-patched ZFS module
  packages = helpers.kernelModuleLLVMOverride (final.linuxKernel.packagesFor kernel) // {
    # CachyOS-patched ZFS for kernel compatibility
    zfs_cachyos = cachyosKernels.zfs-cachyos-lto.override {
      kernel = kernel;
    };
  };
in
{
  inherit kernel packages;
}
