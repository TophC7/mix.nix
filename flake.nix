{
  description = "mix.nix - A NixOS library, modules, and packages collection for infrastructure and desktop";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    # For optional home-manager module support
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./parts/lib.nix
        ./parts/modules.nix
        ./parts/overlays.nix
        ./parts/packages.nix
        ./parts/devshell.nix
      ];

      # Systems to build for (Linux only)
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # Per-system outputs are defined in parts/
      # Flake-wide outputs (lib, modules, overlays) are also in parts/
    };
}
