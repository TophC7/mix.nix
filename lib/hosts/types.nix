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
  inherit (lib) mkOption types;

  # ─────────────────────────────────────────────────────────────
  # USER SPEC - Defined once, referenced by hosts
  # ─────────────────────────────────────────────────────────────

  # Home Manager configuration (optional - presence enables HM)
  homeType = types.submodule {
    options = {
      directory = mkOption {
        type = types.path;
        description = "Path to user's home-manager config directory (auto-imported)";
        example = "./home/users/toph";
      };
    };
  };

  # Base user options
  baseUserOptions = {
    # Allow arbitrary additional attributes for extensions
    freeformType = types.attrsOf types.anything;

    options = {
      name = mkOption {
        type = types.str;
        description = "Username";
        example = "toph";
      };

      uid = mkOption {
        type = types.nullOr types.int;
        description = "User ID (null for auto-assignment)";
        default = null;
        example = 1000;
      };

      group = mkOption {
        type = types.str;
        description = "Primary group";
        default = "users";
      };

      shell = mkOption {
        type = types.package;
        description = "Default shell package";
        example = "pkgs.fish";
      };

      extraGroups = mkOption {
        type = types.listOf types.str;
        description = "Additional groups for the user";
        default = [
          "wheel"
          "networkmanager"
        ];
      };

      # Optional Home Manager config - presence enables HM
      home = mkOption {
        type = types.nullOr homeType;
        description = "Home Manager configuration (null = no HM, just system user)";
        default = null;
      };
    };
  };

  # ─────────────────────────────────────────────────────────────
  # HOST SPEC - References a user by name
  # ─────────────────────────────────────────────────────────────

  # Desktop environment - null means headless/server
  desktopType = types.nullOr (
    types.either types.str (
      types.enum [
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
      freeformType = types.attrsOf types.anything;

      options = {
        # ── Identity ──
        enable = mkOption {
          type = types.bool;
          description = "Whether to build this host configuration";
          default = true;
        };

        hostName = mkOption {
          type = types.str;
          description = "The hostname";
          default = name;
        };

        system = mkOption {
          type = types.enum [
            "x86_64-linux"
            "aarch64-linux"
          ];
          description = "System architecture";
          default = "x86_64-linux";
        };

        # ── User Reference ──
        user = mkOption {
          type = types.str;
          description = "Name of user from mix.users (resolved to full spec at build time)";
          example = "toph";
        };

        # ── Host Type Flags ──
        isServer = mkOption {
          type = types.bool;
          description = "Host is a server (affects defaults like autoLogin)";
          default = false;
        };

        isMinimal = mkOption {
          type = types.bool;
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
          type = types.bool;
          description = "Enable automatic login";
          default = !config.isServer && config.desktop != null;
        };

        # ── Advanced ──
        specialArgs = mkOption {
          type = types.attrsOf types.unspecified;
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

  # User specification type
  userSpec = types.submodule baseUserOptions;

  # Host specification type
  hostSpec = types.submodule baseHostOptions;

  # Factory functions to create extended types
  mkUserSpec =
    extraModule:
    types.submodule (
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
    types.submodule (
      args@{ name, config, ... }:
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

  # Individual types for reuse
  inherit homeType desktopType;
}
