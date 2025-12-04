# Packages aggregator
# Automatically imports all packages in this directory (except default.nix)
#
# To add a new package:
#   1. Create packages/my-tool.nix (or packages/my-tool/default.nix for complex ones)
#   2. Define it as: { lib, pkgs, ... }: stdenv.mkDerivation { pname = "my-tool"; ... }
#   3. It will be automatically picked up and available as packages.my-tool
#
# Package naming: The attribute name is derived from the filename (not pname).
# This keeps overlay evaluation lazy and avoids infinite recursion.
{ lib, pkgs }:

lib.fs.importAttrs ./. { inherit lib pkgs; }
