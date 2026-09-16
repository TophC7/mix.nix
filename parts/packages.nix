# Flake-parts module for packages
{ mixInputs }:
{ lib, inputs, ... }:
let
  # Merge inputs: mix.nix provides base, consumer can override
  # Consumer's inputs take precedence (rightmost wins in //)
  mergedInputs = mixInputs // inputs;
in
{
  # Per-system package outputs
  perSystem =
    { system, ... }:
    let
      # Create pkgs instance that allows unfree packages
      # Some packages (e.g., journey) have unfree licenses, we want to include them
      pkgs = import mergedInputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      # Packages built by this flake
      # Access with: nix build .#packageName
      packages = import ../packages {
        inherit lib pkgs;
        inputs = mergedInputs;
      };
    };
}
