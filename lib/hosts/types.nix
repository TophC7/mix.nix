# Host and User specification type definitions
# Users and Hosts are SEPARATE - hosts reference users by name
#
# Usage:
#   lib.hosts.types.userSpec   # User definition type
#   lib.hosts.types.hostSpec   # Host definition type (references user by name)
#
#   # Extend with your own options
#   lib.hosts.mkHostSpec { options.mounts = lib.mkOption { ... }; }
#   lib.hosts.mkUserSpec { options.email = lib.mkOption { ... }; }
#
{ lib }:

let
  inherit (lib) mkOption;
  # Rename to avoid shadowing with our exported 'types' attribute
  t = lib.types;

  # ─────────────────────────────────────────────────────────────
  # USER SPEC - Defined once, referenced by hosts
  # ─────────────────────────────────────────────────────────────

  # Home Manager configuration (optional - presence enables HM)
  homeType = t.submodule {
    options = {
      directory = mkOption {
        type = t.path;
        description = "Path to user's home-manager config directory (auto-imported)";
        example = "./home/users/toph";
      };
    };
  };

  # Base user options
  baseUserOptions = {
    # Allow arbitrary additional attributes for extensions
    freeformType = t.attrsOf t.anything;

    options = {
      name = mkOption {
        type = t.str;
        description = "Username";
        example = "toph";
      };

      uid = mkOption {
        type = t.nullOr t.int;
        description = "User ID (null for auto-assignment)";
        default = null;
        example = 1000;
      };

      group = mkOption {
        type = t.str;
        description = "Primary group";
        default = "users";
      };

      shell = mkOption {
        type = t.package;
        description = "Default shell package";
        example = "pkgs.fish";
      };

      extraGroups = mkOption {
        type = t.listOf t.str;
        description = "Additional groups for the user";
        default = [
          "wheel"
          "networkmanager"
        ];
      };

      # Optional Home Manager config - presence enables HM
      home = mkOption {
        type = t.nullOr homeType;
        description = "Home Manager configuration (null = no HM, just system user)";
        default = null;
      };
    };
  };

  # ─────────────────────────────────────────────────────────────
  # HOST SPEC - References a user by name
  # ─────────────────────────────────────────────────────────────

  # Desktop environment - null means headless/server
  desktopType = t.nullOr (
    t.either t.str (
      t.enum [
        "gnome"
        "niri"
      ]
    )
  );

  # Base host options
  baseHostOptions =
    { name, config, ... }:
    {
      # Allow arbitrary additional attributes for extensions
      freeformType = t.attrsOf t.anything;

      options = {
        # ── Identity ──
        enable = mkOption {
          type = t.bool;
          description = "Whether to build this host configuration";
          default = true;
        };

        hostName = mkOption {
          type = t.str;
          description = "The hostname";
          default = name;
        };

        system = mkOption {
          type = t.enum [
            "x86_64-linux"
            "aarch64-linux"
          ];
          description = "System architecture";
          default = "x86_64-linux";
        };

        # ── User Reference ──
        user = mkOption {
          type = t.str;
          description = "Name of user from mix.users (resolved to full spec at build time)";
          example = "toph";
        };

        # ── Host Type Flags ──
        isServer = mkOption {
          type = t.bool;
          description = "Host is a server (affects defaults like autoLogin)";
          default = false;
        };

        isMinimal = mkOption {
          type = t.bool;
          description = "Minimal HM config (only coreHomeModules, skip user/host HM directories)";
          default = false;
        };

        # ── Desktop ──
        desktop = mkOption {
          type = desktopType;
          description = "Desktop environment (null for headless)";
          default = null;
          example = "niri";
        };

        autoLogin = mkOption {
          type = t.bool;
          description = "Enable automatic login";
          default = !config.isServer && config.desktop != null;
        };

        # ── Advanced ──
        specialArgs = mkOption {
          type = t.attrsOf t.unspecified;
          description = "Additional specialArgs for nixosSystem";
          default = { };
        };
      };
    };

in
{
  # ─────────────────────────────────────────────────────────────
  # EXPORTS
  # ─────────────────────────────────────────────────────────────

  # Types namespace - contains all type definitions
  types = {
    # User specification type
    userSpec = t.submodule baseUserOptions;

    # Host specification type
    hostSpec = t.submodule baseHostOptions;

    # Individual types for reuse
    inherit homeType desktopType;
  };

  # Factory functions to create extended types (at top level)
  mkUserSpec =
    extraModule:
    t.submodule (
      let
        extra = if builtins.isFunction extraModule then extraModule { } else extraModule;
      in
      {
        inherit (baseUserOptions) freeformType;
        options = baseUserOptions.options // (extra.options or { });
      }
    );

  mkHostSpec =
    extraModule:
    t.submodule (
      args@{ ... }:
      let
        base = baseHostOptions args;
        extra = if builtins.isFunction extraModule then extraModule args else extraModule;
      in
      {
        inherit (base) freeformType;
        options = base.options // (extra.options or { });
        config = (base.config or { }) // (extra.config or { });
      }
    );
}
