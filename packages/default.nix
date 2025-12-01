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
let
  # Import all package files as derivations
  packageFiles = lib.fs.scanNames ./.;

  # Convert filename to package name (remove .nix suffix)
  fileToName =
    fileName: if lib.hasSuffix ".nix" fileName then lib.removeSuffix ".nix" fileName else fileName;

  # Import each file and create an attrset entry using the filename as key
  # IMPORTANT: Don't evaluate drv.pname here - it causes infinite recursion in overlays
  packages = lib.listToAttrs (
    map (fileName: {
      name = fileToName fileName;
      value = import (./. + "/${fileName}") { inherit lib pkgs; };
    }) packageFiles
  );
in
packages
