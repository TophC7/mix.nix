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
# IMPORTANT: Use the CachyOS-patched ZFS userspace; NixOS then loads the
# matching module from kernelPackages.zfs_cachyos:
#   boot.zfs.package = pkgs.zfs_cachyos;
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

  # The kernel set builds with nix-cachyos-kernel's pinned LLVM stdenv (its own
  # glibc), while dependencies like curl come from our nixpkgs. Userspace built
  # there links two glibcs and zpool dies at load once they diverge, so split
  # like nixpkgs' zfs_2_4: module from the kernel stdenv, userspace from ours.
  # zfs-cachyos only forwards `kernel` to zfs/generic.nix, so `configFile` is
  # injected through the callPackage it receives.
  mkZfsCachyos =
    callPackage: configFile:
    callPackage "${inputs.nix-cachyos-kernel}/zfs-cachyos" {
      callPackage = fn: args: callPackage fn (args // { inherit configFile; });
      inputs = { inherit (inputs.nix-cachyos-kernel.inputs) nixpkgs; };
      variant = "linux-cachyos";
    };

  # Apply LLVM fixes and include the CachyOS-patched ZFS module. `self.kernel`
  # is auto-injected; keep upstream's nixpkgs pinned for patch compatibility.
  packages = (helpers.kernelModuleLLVMOverride (final.linuxKernel.packagesFor kernel)).extend (
    self: _super: {
      zfs_cachyos = mkZfsCachyos self.callPackage "kernel";
    }
  );

  zfsUserspace = mkZfsCachyos final.callPackage "user";
in
{
  inherit kernel packages zfsUserspace;
}
