# Flake-parts module for packages
{ lib, inputs, ... }:

{
  # Per-system package outputs
  perSystem =
    { system, ... }:
    let
      # Create pkgs instance that allows unfree packages
      # Some packages (e.g., journey) have unfree licenses, we want to include them
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      # Packages built by this flake
      # Access with: nix build .#packageName
      packages = import ../packages { inherit lib pkgs; };
    };
}
