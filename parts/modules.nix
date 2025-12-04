# Flake-parts module for NixOS and Home Manager modules
{ lib, ... }:

{
  flake = {
    # NixOS modules - import selectively in your configuration:
    #   imports = [ inputs.mix-nix.nixosModules.oci-stacks ];
    #
    # Or import all with:
    #   imports = [ inputs.mix-nix.nixosModules.default ];
    nixosModules = import ../modules/nixos { inherit lib; };

    # Home Manager modules - same pattern:
    #   imports = [ inputs.mix-nix.homeManagerModules.fastfetch ];
    homeManagerModules = import ../modules/home-manager { inherit lib; };
  };
}
