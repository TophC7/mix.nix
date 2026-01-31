# Flake-parts module for nixpkgs overlay
#
# Receives mixInputs from flake.nix closure to forward mix.nix's inputs to consumers.
# This ensures the overlay has access to mix.nix's dependencies (e.g., nix-cachyos-kernel)
# without consumers having to declare them.
#
{ mixInputs }:
{ inputs, ... }:
let
  # Merge inputs: mix.nix provides base, consumer can override
  # Consumer's inputs take precedence (rightmost wins in //)
  mergedInputs = mixInputs // inputs;
in
{
  flake = {
    # Single overlay that provides:
    #   - pkgs.stable.*   (stable channel packages)
    #   - pkgs.unstable.* (unstable channel packages)
    #   - All custom packages from packages/
    #   - All overrides from overlays/overrides/
    #   - pkgs.linuxPackages-ryot* (CachyOS kernels from nix-cachyos-kernel)
    #
    # Usage: nixpkgs.overlays = [ inputs.mix-nix.overlays.default ];
    overlays.default = import ../overlays { inputs = mergedInputs; };
  };
}
