# Packages aggregator
# Automatically imports all packages in this directory (except default.nix)
#
# To add a new package:
#   1. Create packages/my-tool.nix (or packages/my-tool/default.nix for complex ones)
#   2. Define it as: { lib, pkgs, ... }: stdenv.mkDerivation { pname = "my-tool"; ... }
#   3. It will be automatically picked up and available as packages.my-tool
#
# Package naming: The attribute name is derived from the derivation's `pname` attribute.
# For derivations without `pname` (e.g., writeShellScriptBin), `name` is used instead.
{ lib, pkgs }:
let
  # Import all package files as derivations
  packageFiles = lib.fs.scanNames ./.;

  # Import each file and create an attrset entry using the derivation's pname (or name)
  packages = lib.listToAttrs (
    map (
      fileName:
      let
        drv = import (./. + "/${fileName}") { inherit lib pkgs; };
        # Prefer pname if available, fallback to name
        pkgName = drv.pname or drv.name;
      in
      {
        name = pkgName;
        value = drv;
      }
    ) packageFiles
  );
in
packages
