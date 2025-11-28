# Package overrides aggregator
# Automatically imports all modules in this directory (except default.nix)
#
# To add a new override:
#   1. Create overlays/overrides/my-package.nix
#   2. Define it as: { lib, final, prev, stable, unstable }: { my-package = ... }
#   3. It will be automatically picked up
#
# Available in each override file:
#   - lib: extended lib with lib.fs.*, lib.infra.*, lib.desktop.*
#   - final: the final package set (after all overlays)
#   - prev: the previous package set (before this overlay)
#   - stable: stable nixpkgs channel
#   - unstable: unstable nixpkgs channel
{
  lib,
  final,
  prev,
  stable,
  unstable,
}:
# lib.fs.importAndMerge scans this directory and merges all override definitions
lib.fs.importAndMerge ./. {
  inherit
    lib
    final
    prev
    stable
    unstable
    ;
}
