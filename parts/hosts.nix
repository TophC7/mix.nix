# Flake-parts module for declarative host management
#
# This module provides:
#   - `mix.users` option: Define users once (referenced by hosts)
#   - `mix.hosts` option: Define hosts declaratively (reference users by name)
#   - `mix.coreModules` / `mix.coreHomeModules`: Always-applied modules
#   - Automatic `nixosConfigurations` generation
#
# Usage in your flake.nix:
#   imports = [ inputs.mix-nix.flakeModules.hosts ];
#
#   mix = {
#     # Core modules applied to ALL hosts
#     coreModules = [ ./modules/global/core ];
#     coreHomeModules = [ ./home/global/core ];
#
#     # Directory auto-discovery
#     hostsDir = ./hosts;           # NixOS: hosts/<hostname>/
#     hostsHomeDir = ./home/hosts;  # HM: home/hosts/<hostname>/
#
#     # Define users (referenced by hosts)
#     users = {
#       toph = {
#         name = "toph";
#         shell = pkgs.fish;
#         home.directory = ./home/users/toph;  # Enables HM
#       };
#     };
#
#     # Define hosts (reference users by name)
#     hosts = {
#       desktop = {
#         user = "toph";  # String reference to mix.users.toph
#         desktop = "niri";
#       };
#     };
#   };
#
{
  inputs,
  lib,
  config,
  ...
}:

{
  options.mix = {
    # ─────────────────────────────────────────────────────────────
    # USER SPECIFICATIONS
    # ─────────────────────────────────────────────────────────────

    users = lib.mkOption {
      type = lib.types.attrsOf lib.hosts.types.userSpec;
      default = { };
      description = ''
        User definitions (referenced by hosts).
        Users are defined once and can be reused across multiple hosts.
        If a user has `home` configured, Home Manager is enabled for that user.
      '';
      example = lib.literalExpression ''
        {
          toph = {
            name = "toph";
            uid = 1000;
            shell = pkgs.fish;
            home.directory = ./home/users/toph;  # Enables HM
          };
          admin = {
            name = "admin";
            shell = pkgs.bash;
            # No home = no Home Manager
          };
        }
      '';
    };

    # Custom user spec type (for extensions)
    userSpecType = lib.mkOption {
      type = lib.types.raw;
      default = lib.hosts.types.userSpec;
      description = ''
        The type to use for user specifications.
        Override this to add custom options using lib.hosts.mkUserSpec.
      '';
      example = lib.literalExpression ''
        lib.hosts.mkUserSpec {
          options.email = lib.mkOption { type = lib.types.str; };
          options.gpgKey = lib.mkOption { type = lib.types.nullOr lib.types.str; };
        }
      '';
    };

    # ─────────────────────────────────────────────────────────────
    # HOST SPECIFICATIONS
    # ─────────────────────────────────────────────────────────────

    hosts = lib.mkOption {
      type = lib.types.attrsOf lib.hosts.types.hostSpec;
      default = { };
      description = ''
        Declarative host specifications.
        Each host defined here automatically generates a nixosConfiguration.
        Hosts reference users by name (string) from mix.users.
      '';
      example = lib.literalExpression ''
        {
          desktop = {
            user = "toph";  # References mix.users.toph
            desktop = "niri";
          };
          server = {
            user = "admin";  # References mix.users.admin
            isServer = true;
            system = "aarch64-linux";
          };
        }
      '';
    };

    # Custom host spec type (for extensions)
    hostSpecType = lib.mkOption {
      type = lib.types.raw;
      default = lib.hosts.types.hostSpec;
      description = ''
        The type to use for host specifications.
        Override this to add custom options using lib.hosts.mkHostSpec.
      '';
      example = lib.literalExpression ''
        lib.hosts.mkHostSpec {
          options.mounts = lib.mkOption { ... };
          options.network.vpn = lib.mkOption { ... };
        }
      '';
    };

    # ─────────────────────────────────────────────────────────────
    # CORE MODULES - Applied to ALL hosts
    # ─────────────────────────────────────────────────────────────

    coreModules = lib.mkOption {
      type = lib.types.listOf lib.types.deferredModule;
      default = [ ];
      description = ''
        NixOS modules applied to EVERY host.
        Use this for your global/core configurations.
      '';
      example = lib.literalExpression ''
        [
          ./modules/global/core
          ./modules/global/nix-settings.nix
        ]
      '';
    };

    coreHomeModules = lib.mkOption {
      type = lib.types.listOf lib.types.deferredModule;
      default = [ ];
      description = ''
        Home Manager modules applied to EVERY host (that has HM enabled).
        Use this for your global/core home configurations.
      '';
      example = lib.literalExpression ''
        [
          ./home/global/core
          ./home/global/shell.nix
        ]
      '';
    };

    # ─────────────────────────────────────────────────────────────
    # OPTIONAL CONFIGURATION
    # ─────────────────────────────────────────────────────────────

    hostsDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Directory containing per-host NixOS configurations.
        Hosts are auto-imported from: <hostsDir>/<hostname>/
      '';
      example = lib.literalExpression "./hosts";
    };

    hostsHomeDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Directory containing per-host Home Manager configurations.
        Host HM configs are auto-imported from: <hostsHomeDir>/<hostname>/
      '';
      example = lib.literalExpression "./home/hosts";
    };

    homeManager = lib.mkOption {
      type = lib.types.nullOr lib.types.attrs;
      default = inputs.home-manager or null;
      description = ''
        Home Manager input for automatic integration.
        Defaults to inputs.home-manager if available.
      '';
    };
  };

  config = {
    flake = {
      # Generate nixosConfigurations from host specs
      nixosConfigurations = lib.hosts.mkHosts {
        specs = config.mix.hosts;
        users = config.mix.users;
        inherit inputs;
        inherit (config.mix)
          hostsDir
          hostsHomeDir
          coreModules
          coreHomeModules
          homeManager
          ;
      };

      # Expose the flake-parts module for consumers
      flakeModules.hosts = ./hosts.nix;
    };
  };
}
