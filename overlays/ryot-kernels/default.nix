# CachyOS-based kernel variants
#
# Provides optimized kernel configurations for different workloads:
# - linuxPackages-ryot:     Desktop/gaming (low latency, ThinLTO)
# - linuxPackages-ryot-zfs: ZFS servers (balanced, includes zfs_cachyos)
# - linuxPackages-ryot-net: Routers/network appliances (throughput-focused)
#
# Usage:
#   boot.kernelPackages = pkgs.linuxPackages-ryot;
#
# For ZFS hosts:
#   boot.kernelPackages = pkgs.linuxPackages-ryot-zfs;
#   boot.zfs.package = config.boot.kernelPackages.zfs_cachyos;
{
  lib,
  final,
  prev,
  inputs,
  stable,
  unstable,
}:
let
  inherit (final.stdenv.hostPlatform) system;

  # CachyOS kernel packages from the flake
  cachyosKernels = inputs.nix-cachyos-kernel.legacyPackages.${system};

  # Helper for LTO kernel module compatibility
  helpers = final.callPackage "${inputs.nix-cachyos-kernel}/helpers.nix" { };

  # Import kernel definitions
  kernelRyot = import ./kernel-ryot.nix {
    inherit
      lib
      final
      inputs
      helpers
      cachyosKernels
      ;
  };

  kernelRyotZfs = import ./kernel-ryot-zfs.nix {
    inherit
      lib
      final
      inputs
      helpers
      cachyosKernels
      ;
  };

  kernelRyotNet = import ./kernel-ryot-net.nix {
    inherit
      lib
      final
      inputs
      helpers
      cachyosKernels
      ;
  };
in
{
  # Desktop/Gaming
  linux-ryot = kernelRyot.kernel;
  linuxPackages-ryot = kernelRyot.packages;

  # ZFS Servers
  linux-ryot-zfs = kernelRyotZfs.kernel;
  linuxPackages-ryot-zfs = kernelRyotZfs.packages;

  # Network/Router
  linux-ryot-net = kernelRyotNet.kernel;
  linuxPackages-ryot-net = kernelRyotNet.packages;
}
