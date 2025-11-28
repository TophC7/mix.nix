# Packages aggregator
# Automatically imports all modules in this directory (except default.nix)
#
# To add a new package:
#   1. Create packages/my-tool.nix (or packages/my-tool/default.nix for complex ones)
#   2. Define it as: { lib, pkgs }: { my-tool = pkgs.callPackage ... }
#   3. It will be automatically picked up and available as pkgs.my-tool
{ lib, pkgs }:
# lib.fs.importAndMerge scans this directory and merges all package definitions
lib.fs.importAndMerge ./. { inherit lib pkgs; }
