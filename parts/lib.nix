# Flake-parts module for library functions
{ inputs, ... }:

let
  # Extend nixpkgs.lib with our custom functions
  # This is THE lib for this entire config - use it everywhere
  lib = (import ../lib) inputs.nixpkgs.lib;
in
{
  # Make extended lib available to other flake-parts modules
  _module.args.lib = lib;

  flake = {
    # Expose extended lib as flake output
    # Consumers get: lib.fs.scanPaths, lib.infra.*, lib.desktop.*
    # Plus all of nixpkgs.lib (lib.mkOption, lib.types, etc.)
    inherit lib;
  };
}
