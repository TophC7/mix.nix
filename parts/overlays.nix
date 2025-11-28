# Flake-parts module for nixpkgs overlay
{ inputs, ... }:

{
  flake = {
    # Single overlay that provides:
    #   - pkgs.stable.*   (stable channel packages)
    #   - pkgs.unstable.* (unstable channel packages)
    #   - All custom packages from packages/
    #   - All overrides from overlays/overrides/
    #
    # Usage: nixpkgs.overlays = [ inputs.lib-nix.overlays.default ];
    overlays.default = import ../overlays { inherit inputs; };
  };
}
