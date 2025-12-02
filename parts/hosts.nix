# Flake-parts module for declarative host management
#
# This module provides:
#   - `mix.users` option: Define users once (referenced by hosts)
#   - `mix.hosts` option: Define hosts declaratively (reference users by name)
#   - `mix.coreModules` / `mix.coreHomeModules`: Always-applied modules
#   - Automatic `nixosConfigurations` generation
#
# Usage in your flake.nix (basic):
#   imports = [ inputs.mix-nix.flakeModules.hosts ];
#
# Usage with extended types (custom options on hosts/users):
#   imports = [
#     (inputs.mix-nix.flakeModules.hosts {
#       hostSpecType = lib.hosts.mkHostSpec {
#         options.mounts = lib.mkOption { ... };
#       };
#     })
#   ];
#
# Configuration:
#   mix = {
#     # Core modules applied to ALL hosts
#     coreModules = [ ./modules/global/core ];
#     coreHomeModules = [ ./home/global/core ];
#
#     # Directory auto-discovery (supports both dirs and flat files)
#     hostsDir = ./hosts;           # NixOS: hosts/<hostname>/ or hosts/<hostname>.nix
#     hostsHomeDir = ./home/hosts;  # HM: home/hosts/<hostname>/ or home/hosts/<hostname>.nix
#     usersHomeDir = ./home/users;  # HM: home/users/<username>/ or home/users/<username>.nix
#
#     # Define users (referenced by hosts)
#     # HM auto-enabled if file exists in usersHomeDir
#     users = {
#       toph = {
#         name = "toph";
#         shell = pkgs.fish;
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

# Module factory pattern:
# - Direct import: imports = [ inputs.mix-nix.flakeModules.hosts ]
# - With custom types: imports = [ (inputs.mix-nix.flakeModules.hosts { hostSpecType = ...; }) ]

args:
let
  # Detect if flake-parts is calling us directly (passes 'self' from flake internals)
  isFlakePartsCall = args ? self;

  # Build module with given spec types
  mkModule =
    { hostSpecType, userSpecType }:
    {
      inputs,
      lib,
      config,
      ...
    }:
    let
      actualHostSpecType = if hostSpecType != null then hostSpecType else lib.hosts.types.hostSpec;
      actualUserSpecType = if userSpecType != null then userSpecType else lib.hosts.types.userSpec;
    in

    {
      options.mix = {
        # ─────────────────────────────────────────────────────────────
        # USER SPECIFICATIONS
        # ─────────────────────────────────────────────────────────────

        users = lib.mkOption {
          type = lib.types.attrsOf actualUserSpecType;
          default = { };
          description = ''
            User definitions (referenced by hosts).
            Users are defined once and can be reused across multiple hosts.
            Home Manager is auto-enabled if a config exists in usersHomeDir/<username>.

            To extend with custom options, call this module with userSpecType:
              imports = [ (inputs.mix-nix.flakeModules.hosts {
                userSpecType = lib.hosts.mkUserSpec { options.email = ...; };
              }) ];
          '';
          example = lib.literalExpression ''
            {
              toph = {
                name = "toph";
                uid = 1000;
                shell = pkgs.fish;
                # HM auto-enabled if usersHomeDir/toph.nix or usersHomeDir/toph/ exists
              };
              admin = {
                name = "admin";
                shell = pkgs.bash;
                # No HM if no file exists in usersHomeDir
              };
            }
          '';
        };

        # ─────────────────────────────────────────────────────────────
        # HOST SPECIFICATIONS
        # ─────────────────────────────────────────────────────────────

        hosts = lib.mkOption {
          type = lib.types.attrsOf actualHostSpecType;
          default = { };
          description = ''
            Declarative host specifications.
            Each host defined here automatically generates a nixosConfiguration.
            Hosts reference users by name (string) from mix.users.

            To extend with custom options, call this module with hostSpecType:
              imports = [ (inputs.mix-nix.flakeModules.hosts {
                hostSpecType = lib.hosts.mkHostSpec { options.mounts = ...; };
              }) ];
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
            Supports both directory and flat file structures:
              - Directory: <hostsDir>/<hostname>/ (with default.nix)
              - Flat file: <hostsDir>/<hostname>.nix
            Directories take precedence if both exist.
          '';
          example = lib.literalExpression "./hosts";
        };

        hostsHomeDir = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Directory containing per-host Home Manager configurations.
            Supports both directory and flat file structures:
              - Directory: <hostsHomeDir>/<hostname>/ (with default.nix)
              - Flat file: <hostsHomeDir>/<hostname>.nix
            Directories take precedence if both exist.
          '';
          example = lib.literalExpression "./home/hosts";
        };

        usersHomeDir = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Directory containing per-user Home Manager configurations.
            Supports both directory and flat file structures:
              - Directory: <usersHomeDir>/<username>/ (with default.nix)
              - Flat file: <usersHomeDir>/<username>.nix
            Directories take precedence if both exist.
            Home Manager is automatically enabled for users whose config exists here.
          '';
          example = lib.literalExpression "./home/users";
        };

        homeManager = lib.mkOption {
          type = lib.types.nullOr lib.types.attrs;
          default = inputs.home-manager or null;
          description = ''
            Home Manager input for automatic integration.
            Defaults to inputs.home-manager if available.
          '';
        };

        specialArgs = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = ''
            Global special arguments available to ALL hosts and Home Manager modules.
            These are merged with per-host specialArgs, with per-host values taking precedence.
          '';
          example = lib.literalExpression ''
            { inherit flakeRoot; }
          '';
        };
      };

      config = {
        flake = {
          # Generate nixosConfigurations from host specs
          nixosConfigurations = lib.hosts.mkHosts {
            specs = config.mix.hosts;
            users = config.mix.users;
            secrets = config.mix.secrets.loaded or { };
            inherit inputs;
            inherit (config.mix)
              hostsDir
              hostsHomeDir
              usersHomeDir
              coreModules
              coreHomeModules
              homeManager
              specialArgs
              ;
          };
        };
      };
    };

in
if isFlakePartsCall then
  # Direct import - use default types
  mkModule {
    hostSpecType = null;
    userSpecType = null;
  } args
else
  # Factory call - return module function with custom types
  mkModule {
    hostSpecType = args.hostSpecType or null;
    userSpecType = args.userSpecType or null;
  }
