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

    # For theme generation (Material You colors from wallpaper)
    matugen = {
      url = "github:InioX/Matugen";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      # Extend nixpkgs.lib with our custom functions BEFORE entering flake-parts
      # This must be done here so it can be passed via specialArgs
      lib = (import ./lib) inputs.nixpkgs.lib;
    in
    flake-parts.lib.mkFlake {
      inherit inputs;
      # specialArgs has highest priority - cannot be shadowed by module function arguments
      specialArgs = { inherit lib; };
    } {
      imports = [
        ./parts/modules.nix
        ./parts/overlays.nix
        ./parts/packages.nix
        ./parts/devshell.nix
        ./parts/hosts.nix
      ];

      # Systems to build for (Linux only)
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # Expose extended lib as flake output
      flake.lib = lib;
    };
}
