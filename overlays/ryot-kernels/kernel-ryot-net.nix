# Network/Router kernel - optimized for packet throughput
#
# Best for:
# - Routers and firewalls
# - Network appliances
# - Low-resource systems (2-4GB RAM)
#
# Key characteristics:
# - Throughput over latency (voluntary preemption)
# - Low interrupt overhead (300Hz timer)
# - No LTO for faster builds and smaller footprint
# - x86_64-v2 for broader compatibility
# - Performance governor for consistent routing
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
    pname = "linux-ryot-net";

    # Compiler & Optimization (no LTO for faster builds)
    lto = "none";
    processorOpt = "x86_64-v2"; # Broader compatibility for embedded/router hardware
    ccHarder = true;

    # Scheduler & Throughput (network-optimized)
    cpusched = "bore";
    hzTicks = "300"; # Lower interrupt overhead for packet processing
    tickrate = "full"; # CPU can sleep between packet bursts
    preemptType = "voluntary"; # Better throughput, less context switching

    # Network
    bbr3 = true; # Modern TCP congestion control

    # Memory
    hugepage = "madvise"; # Conservative for low-RAM systems

    # Router-specific
    performanceGovernor = true; # Consistent performance, no frequency scaling

    # Defaults
    kcfi = false;
    hardened = false;
    handheld = false;
    rt = false;
    acpiCall = false;
    autoModules = true;
  };

  # No LTO, standard kernel packages work
  packages = final.linuxKernel.packagesFor kernel;
in
{
  inherit kernel packages;
}
