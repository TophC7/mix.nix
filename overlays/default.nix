# Main overlay - provides stable/unstable channels, packages, and overrides
#
# Usage: nixpkgs.overlays = [ inputs.lib-nix.overlays.default ];
#
# This gives you:
#   pkgs.stable.*    - packages from stable nixpkgs
#   pkgs.unstable.*  - packages from unstable nixpkgs
#   pkgs.<custom>    - custom packages from packages/
#   Overridden packages from overlays/overrides/
{ inputs }:
final: prev:
let
  # Extend lib here (not inherited from flake)
  # overlays run in the consumer's nixpkgs context
  # where prev.lib is plain nixpkgs lib
  lib = (import ../lib) prev.lib;

  inherit (final.stdenv.hostPlatform) system;

  # Stable and unstable channel access
  channels = {
    stable = import inputs.nixpkgs-stable {
      inherit system;
      config.allowUnfree = true;
    };
    unstable = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  };

  # Import all custom packages
  packages = import ../packages {
    inherit lib;
    pkgs = final;
  };

  # Import all overrides
  overrides = import ./overrides {
    inherit lib final prev;
    inherit (channels) stable unstable;
  };
in
channels // packages // overrides
