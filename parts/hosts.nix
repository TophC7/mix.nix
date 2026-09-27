# Flake-parts module for declarative host management
#
# This module provides:
#   - `mix.users` option: Define users once (referenced by hosts)
#   - `mix.hosts` option: Define hosts declaratively (reference users by name)
#   - `mix.hostSpecExtensions` / `mix.userSpecExtensions`: Composable type extensions
#   - `mix.apiVersion`: Configuration API version (1 default/deprecated, 2 current)
#   - `mix.extends`: v2-only fallback layout root (e.g. a sibling flake reusing core/features)
#   - `mix.coreModules` / `mix.coreHomeModules` / `mix.hostsDir` / `mix.hostsHomeDir` /
#     `mix.usersHomeDir`: v1-only locations (v2 uses a fixed layout)
#   - Automatic `nixosConfigurations` generation
#
# Usage in your flake.nix:
#   imports = [ inputs.mix-nix.flakeModules.hosts ];
#
# Extending with custom options (e.g. hostSpec.nix in your repository):
#   config.mix.hostSpecExtensions = [ ./hostSpec.nix ];
#
#   # Where hostSpec.nix is a module adding options:
#   { lib, ... }: {
#     options.desktop = lib.mkOption { ... };
#     options.greeter = lib.mkOption { ... };
#   }
#
# Configuration (API v2): the layout is fixed, relative to the flake root (inputs.self):
#   hosts/<hostname>/          host NixOS (or hosts/<hostname>.nix); home/ or home.nix inside
#                              a host directory is that host's HM for its enrolled user
#   modules/core/              NixOS for every host (or modules/core.nix); home/ or home.nix
#                              inside it goes to home-manager.sharedModules
#   modules/users/<username>/  HM profile (or <username>.nix); enrolls the user
#   modules/features/<name>/   nixos.nix and/or home.nix, loaded with lib.features [ "<name>" ]
#
#   mix = {
#     apiVersion = 2;
#     users.toph = {
#       name = "toph";
#       shell = "fish";
#     };
#     hosts.desktop = {
#       user = "toph";  # String reference to mix.users.toph
#       desktop = "gnome";  # From hostSpecExtensions
#     };
#   };
#
# API v1 (default when mix.apiVersion is omitted; deprecated, emits one warning):
#   mix = {
#     coreModules = [ ./modules/global/core ];
#     coreHomeModules = [ ./home/global/core ];
#     hostsDir = ./hosts;
#     hostsHomeDir = ./home/hosts;  # HM: home/hosts/<hostname>/ or home/hosts/<hostname>.nix
#     usersHomeDir = ./home/users;  # HM: home/users/<username>/ or home/users/<username>.nix
#     users.toph = { name = "toph"; shell = "fish"; };  # HM auto-enabled if file exists in usersHomeDir
#     hosts.desktop.user = "toph";
#   };
#   v1 will be removed in a future breaking update; omitted/1 will then fail with
#   migration guidance instead of silently switching to v2.
#

# Receives mixInputs from flake.nix closure to forward mix.nix's inputs to consumers
{ mixInputs }:
{
  inputs,
  lib,
  config,
  options,
  ...
}:
let
  # Merge inputs: mix.nix provides base, consumer can override
  # Consumer's inputs take precedence (rightmost wins in //)
  mergedInputs = mixInputs // inputs;

  # Forward version-specific options only when explicitly defined, so the other version
  # rejects even explicit [ ]/null while ignoring declared defaults. The declaration's
  # default is a lone mkOptionDefault (priority 1500) entry; any stronger or extra
  # same-priority definition is explicit. Definitions weaker than the default never take effect.
  explicitVersionOnly = lib.filterAttrs (
    name: _:
    let
      opt = options.mix.${name};
    in
    opt.highestPrio < (lib.mkOptionDefault null).priority
    || builtins.length opt.definitionsWithLocations > 1
  ) {
    inherit (config.mix)
      coreModules
      coreHomeModules
      hostsDir
      hostsHomeDir
      usersHomeDir
      extends
      ;
  };

  # v1 keeps the public builder's shape (with isMinimal); v2 builds from the bare base
  hostSpecType =
    if config.mix.apiVersion == 1 then
      lib.hosts.mkHostSpecType config.mix.hostSpecExtensions
    else
      lib.types.submoduleWith {
        modules = [ lib.hosts.modules.baseHostSpec ] ++ config.mix.hostSpecExtensions;
      };

  # v1's isMinimal changed Home Manager; under v2 an undeclared (freeform) isMinimal would
  # be silently ignored, so migrated configs fail loudly instead
  strayMinimal = lib.attrNames (lib.filterAttrs (_: spec: spec ? isMinimal) config.mix.hosts);
  checkMinimal =
    if config.mix.apiVersion == 2 && strayMinimal != [ ] && !(hostSpecType.getSubOptions [ ] ? isMinimal) then
      throw "mix.nix: apiVersion = 2 has no isMinimal (set on: ${lib.concatStringsSep ", " strayMinimal}). Remove it, or declare it via mix.hostSpecExtensions and read host.isMinimal in your modules."
    else
      lib.id;
in
{
  options.mix = {
    # ─────────────────────────────────────────────────────────────
    # API VERSION
    # ─────────────────────────────────────────────────────────────

    apiVersion = lib.mkOption {
      # Plain int: lib.hosts.mkHosts validates (1 or 2) and emits migration guidance
      type = lib.types.int;
      default = 1;
      description = ''
        Configuration API version (1 or 2).
        1 (default, deprecated): original API; locations come from hostsDir, hostsHomeDir,
        usersHomeDir, coreModules and coreHomeModules. Evaluating it emits one deprecation
        warning. Set 2 after migrating.
        2: fixed layout under the flake root (hosts/, modules/core, modules/features/,
        modules/users/); the v1 location options are rejected when set (even to [ ] or null).
        extends is v2-only; v1 rejects it when set.
        A future breaking update will remove v1; omitted/1 will then fail with migration
        guidance rather than silently switching to v2.
      '';
      example = 2;
    };

    # ─────────────────────────────────────────────────────────────
    # TYPE EXTENSIONS - Allow other flakes to extend specs
    # ─────────────────────────────────────────────────────────────

    hostSpecExtensions = lib.mkOption {
      type = lib.types.listOf lib.types.deferredModule;
      default = [ ];
      description = ''
        Modules to compose into the hostSpec type.
        Extensions can add options that become available on all hosts.

        Example extension module (e.g., adding desktop options):
          { lib, ... }: {
            options.desktop = lib.mkOption {
              type = lib.types.submodule { ... };
              default = { };
            };
          }
      '';
      example = lib.literalExpression ''
        [
          # From hostSpec extension
          ({ lib, ... }: {
            options.desktop.niri.enable = lib.mkEnableOption "Niri compositor";
            options.greeter.type = lib.mkOption { type = lib.types.str; default = "tuigreet"; };
          })
        ]
      '';
    };

    userSpecExtensions = lib.mkOption {
      type = lib.types.listOf lib.types.deferredModule;
      default = [ ];
      description = ''
        Modules to compose into the userSpec type.
        Extensions can add options that become available on all users.
      '';
      example = lib.literalExpression ''
        [
          ({ lib, ... }: {
            options.email = lib.mkOption { type = lib.types.str; };
            options.gpgKey = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
          })
        ]
      '';
    };

    # ─────────────────────────────────────────────────────────────
    # USER SPECIFICATIONS
    # ─────────────────────────────────────────────────────────────

    users = lib.mkOption {
      # Type is built lazily from base + extensions
      type = lib.types.attrsOf (lib.hosts.mkUserSpecType config.mix.userSpecExtensions);
      default = { };
      description = ''
        User definitions (referenced by hosts).
        Users are defined once and can be reused across multiple hosts.
        Home Manager enrollment: a user is enrolled (home-manager.users.<name>) only
        when its profile exists (v2: modules/users/<name>; v1: usersHomeDir/<name>).
        v2: Home Manager integration loads whenever mix.homeManager is non-null.
        v1: Home Manager integration loads only for users with a profile.

        To extend with custom options, add modules to mix.userSpecExtensions.
      '';
      example = lib.literalExpression ''
        {
          toph = {
            name = "toph";
            uid = 1000;
            shell = pkgs.fish;
          };
          admin = {
            name = "admin";
            shell = pkgs.bash;
          };
        }
      '';
    };

    # ─────────────────────────────────────────────────────────────
    # HOST SPECIFICATIONS
    # ─────────────────────────────────────────────────────────────

    hosts = lib.mkOption {
      type = lib.types.attrsOf hostSpecType;
      default = { };
      description = ''
        Declarative host specifications.
        Each host defined here automatically generates a nixosConfiguration.
        Hosts reference users by name (string) from mix.users.

        To extend with custom options, add modules to mix.hostSpecExtensions.
      '';
      example = lib.literalExpression ''
        {
          desktop = {
            user = "toph";  # References mix.users.toph
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
    # V2 LAYOUT
    # ─────────────────────────────────────────────────────────────

    extends = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        API v2 only: another layout root this flake builds on. Hosts, users and
        features resolve in this flake first, then in the extended root; the extended
        root's modules/core applies before this flake's own. One level only (the
        extended root's own extends is not followed).
        Rejected under apiVersion = 1 (even null).
      '';
      example = lib.literalExpression "../.";
    };

    # ─────────────────────────────────────────────────────────────
    # V1 LOCATIONS (rejected under apiVersion = 2)
    # ─────────────────────────────────────────────────────────────

    coreModules = lib.mkOption {
      type = lib.types.listOf lib.types.deferredModule;
      default = [ ];
      description = ''
        API v1 only: NixOS modules applied to EVERY host.
        v2 imports modules/core instead; rejected under apiVersion = 2 (even [ ]).
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
        API v1 only: Home Manager modules applied to EVERY host (that has HM enabled).
        v2 shares modules/core/home instead; rejected under apiVersion = 2 (even [ ]).
      '';
      example = lib.literalExpression ''
        [
          ./home/global/core
          ./home/global/shell.nix
        ]
      '';
    };

    hostsDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        API v1 only: directory containing per-host NixOS configurations
        (<hostsDir>/<hostname>/ or <hostsDir>/<hostname>.nix; directories first).
        v2 uses hosts/ at the flake root; rejected under apiVersion = 2 (even null).
      '';
      example = lib.literalExpression "./hosts";
    };

    hostsHomeDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        API v1 only: directory containing per-host Home Manager configurations
        (<hostsHomeDir>/<hostname>/ or <hostsHomeDir>/<hostname>.nix; directories first).
        v2 uses hosts/<hostname>/home instead; rejected under apiVersion = 2 (even null).
      '';
      example = lib.literalExpression "./home/hosts";
    };

    usersHomeDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        API v1 only: directory containing per-user Home Manager profiles
        (<usersHomeDir>/<username>/ or <usersHomeDir>/<username>.nix; directories first).
        A user is enrolled in Home Manager only when its profile exists here.
        v2 uses modules/users/ instead; rejected under apiVersion = 2 (even null).
      '';
      example = lib.literalExpression "./home/users";
    };

    # ─────────────────────────────────────────────────────────────
    # OPTIONAL CONFIGURATION
    # ─────────────────────────────────────────────────────────────

    homeManager = lib.mkOption {
      type = lib.types.nullOr lib.types.attrs;
      default = inputs.home-manager or null;
      description = ''
        Home Manager input for automatic integration.
        Defaults to inputs.home-manager if available.
        v1: integration also requires the user's usersHomeDir profile.
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

    # ─────────────────────────────────────────────────────────────
    # INTERNAL - mix.nix's inputs (exposed for extension flakes)
    # ─────────────────────────────────────────────────────────────

    mixInputs = lib.mkOption {
      type = lib.types.attrs;
      default = mixInputs;
      readOnly = true;
      description = ''
        mix.nix's original flake inputs.
        Available for extension flakes that need to access
        mix.nix's dependencies without consumers having to redeclare them.

        This is automatically set from mix.nix's inputs and merged with consumer
        inputs. Consumer inputs take precedence.
      '';
    };
  };

  config = {
    flake = {
      # Generate nixosConfigurations from host specs
      nixosConfigurations = checkMinimal (lib.hosts.mkHosts (
        {
          specs = config.mix.hosts;
          users = config.mix.users;
          secrets = config.mix.secrets.loaded or { };
          # Use merged inputs: mix.nix's inputs + consumer's inputs (consumer wins)
          inputs = mergedInputs;
          inherit (config.mix)
            homeManager
            specialArgs
            apiVersion
            ;
        }
        // explicitVersionOnly
      ));
    };
  };
}
