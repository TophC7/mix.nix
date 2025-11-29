# Flake-parts module for NixOS and Home Manager modules
{ inputs, lib, ... }:

{
  flake = {
    # NixOS modules - import selectively in your configuration:
    #   imports = [ myLib.nixosModules.containers ];
    #
    # Or import all with:
    #   imports = [ myLib.nixosModules.default ];
    nixosModules = import ../modules/nixos { inherit inputs lib; };

    # Home Manager modules - same pattern:
    #   imports = [ myLib.homeManagerModules.colors ];
    homeManagerModules = import ../modules/home-manager { inherit inputs lib; };
  };
}
