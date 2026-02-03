{
  description = "mix.nix - A NixOS library, modules, and packages collection for infrastructure and desktop";

  inputs = {
    # Pinned to known-working revision (pre-env validation breakage)
    # TODO: Return to nixos-unstable once treewide NIX_LDFLAGS fix lands
    nixpkgs.url = "github:NixOS/nixpkgs/62c8382960464ceb98ea593cb8321a2cf8f9e3e5";
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

    # CachyOS kernel flake for custom kernel builds
    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel/release";
      # Do NOT override nixpkgs to avoid kernel/patch version mismatch
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      # Extend nixpkgs.lib with our custom functions BEFORE entering flake-parts
      # This must be done here so it can be passed via specialArgs
      lib = (import ./lib) inputs.nixpkgs.lib;

      # Capture mix.nix's inputs for forwarding to consumers
      # This allows consumers to use mix.nix's dependencies (e.g., nix-cachyos-kernel)
      # without having to declare them in their own flake.nix
      mixInputs = inputs;
    in
    flake-parts.lib.mkFlake
      {
        inherit inputs;
        # specialArgs has highest priority - cannot be shadowed by module function arguments
        specialArgs = { inherit lib; };
      }
      {
        imports = [ (import ./parts/default.nix { inherit mixInputs; }) ];

        # Systems to build for (Linux only)
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];

        # Expose extended lib as flake output
        flake.lib = lib;
      }
    # Direct flake outputs - wrap modules to capture mixInputs in closure
    // {
      flakeModules = {
        default = import ./parts/default.nix { inherit mixInputs; };
        hosts = import ./parts/hosts.nix { inherit mixInputs; };
        secrets = ./parts/secrets.nix;
        modules = ./parts/modules.nix;
        overlays = import ./parts/overlays.nix { inherit mixInputs; };
        packages = ./parts/packages.nix;
        devshell = ./parts/devshell.nix;
      };
    };
}
