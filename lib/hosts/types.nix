# Host and User specification type definitions
# Users and Hosts are SEPARATE - hosts reference users by name
#
# Usage:
#   lib.hosts.types.userSpec   # User definition type
#   lib.hosts.types.hostSpec   # Host definition type (references user by name)
#
#   # For composable extensions (used by parts/hosts.nix):
#   lib.hosts.modules.baseUserSpec   # Base user module (for submoduleWith imports)
#   lib.hosts.modules.baseHostSpec   # Base host module (for submoduleWith imports)
#
#   # Build types with extensions:
#   lib.hosts.mkUserSpecType [ extraModule1 extraModule2 ]
#   lib.hosts.mkHostSpecType [ extraModule1 extraModule2 ]
#
{ lib }:

let
  inherit (lib) mkOption;
  # Rename to avoid shadowing with our exported 'types' attribute
  t = lib.types;

  # ─────────────────────────────────────────────────────────────
  # USER SPEC - Defined once, referenced by hosts
  # ─────────────────────────────────────────────────────────────

  # Base user options module (can be used with submoduleWith imports)
  # Home Manager is auto-enabled via usersHomeDir discovery (no explicit option needed)
  baseUserSpec = {
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
        type = t.either t.package t.str;
        description = "Default shell package or name (string resolved at build time via pkgs)";
        example = "fish";
      };

      extraGroups = mkOption {
        type = t.listOf t.str;
        description = "Additional groups for the user";
        default = [
          "wheel"
          "networkmanager"
        ];
      };
    };
  };

  # ─────────────────────────────────────────────────────────────
  # HOST SPEC - References a user by name
  # ─────────────────────────────────────────────────────────────

  # Base host options module (can be used with submoduleWith imports)
  baseHostSpec =
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
          description = "Host is a server";
          default = false;
        };

        isMinimal = mkOption {
          type = t.bool;
          description = "Minimal HM config (only coreHomeModules, skip user/host HM directories)";
          default = false;
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

  # Base modules - for composable extension via submoduleWith imports
  modules = {
    baseUserSpec = baseUserSpec;
    baseHostSpec = baseHostSpec;
  };

  # Types namespace - contains default (non-extended) type definitions
  types = {
    # User specification type (default, no extensions)
    userSpec = t.submodule baseUserSpec;

    # Host specification type (default, no extensions)
    hostSpec = t.submodule baseHostSpec;
  };

  # ─────────────────────────────────────────────────────────────
  # TYPE BUILDERS - Create types with extensions
  # ─────────────────────────────────────────────────────────────

  # Build a userSpec type from a list of extension modules
  # Usage: mkUserSpecType [ ./extensions/email.nix ./extensions/gpg.nix ]
  mkUserSpecType =
    extensionModules:
    t.submoduleWith {
      modules = [ baseUserSpec ] ++ extensionModules;
    };

  # Build a hostSpec type from a list of extension modules
  # Usage: mkHostSpecType [ ./extensions/desktop.nix ./extensions/gaming.nix ]
  mkHostSpecType =
    extensionModules:
    t.submoduleWith {
      modules = [ baseHostSpec ] ++ extensionModules;
    };
}
