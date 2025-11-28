# Flake-parts module for packages
{ inputs, ... }:

let
  # Get extended lib
  lib = (import ../lib) inputs.nixpkgs.lib;
in
{
  # Per-system package outputs
  perSystem =
    { pkgs, system, ... }:
    {
      # Packages built by this flake
      # Access with: nix build .#packageName
      packages = import ../packages { inherit lib pkgs; };
    };
}
