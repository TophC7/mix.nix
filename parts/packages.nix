# Flake-parts module for packages
{ lib, ... }:

{
  # Per-system package outputs
  perSystem =
    { pkgs, ... }:
    {
      # Packages built by this flake
      # Access with: nix build .#packageName
      packages = import ../packages { inherit lib pkgs; };
    };
}
