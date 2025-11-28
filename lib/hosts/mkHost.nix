# Host builder functions
# Transforms host specifications into NixOS configurations
#
# Users and Hosts are SEPARATE:
#   - Users defined in mix.users
#   - Hosts reference users by name (string)
#   - User is resolved at build time and merged into host.user
#
# Usage:
#   lib.hosts.mkHost { name = "myhost"; spec = { ... }; users = { ... }; inherit inputs; }
#   lib.hosts.mkHosts { specs = { ... }; users = { ... }; inherit inputs; }
#
{ lib }:

let
  inherit (lib) mkIf optional optionalAttrs;

  # ─────────────────────────────────────────────────────────────
  # SINGLE HOST BUILDER
  # ─────────────────────────────────────────────────────────────

  mkHost =
    {
      # The hostname (attrset key)
      name,
      # The evaluated host specification
      spec,
      # User definitions (attrset)
      users,
      # Inputs from the flake
      inputs,
      # Optional: path to hosts directory for NixOS auto-discovery
      hostsDir ? null,
      # Optional: path to home/hosts directory for HM auto-discovery
      hostsHomeDir ? null,
      # CORE NixOS modules - applied to ALL hosts
      coreModules ? [ ],
      # CORE Home Manager modules - applied to ALL users with HM
      coreHomeModules ? [ ],
      # Optional: Home Manager input
      homeManager ? null,
    }:
    let
      # ── Resolve user from reference ──
      user =
        users.${spec.user}
          or (throw "Host '${name}' references unknown user '${spec.user}'. Available users: ${builtins.concatStringsSep ", " (builtins.attrNames users)}");

      # Home Manager enabled only if user has home config
      hmEnabled = user.home != null;

      # Home directory path
      homeDir = "/home/${user.name}";

      # Host-specific home config path (for auto-discovery)
      hostHomePath = hostsHomeDir + "/${name}";
      hasHostHome = hostsHomeDir != null && builtins.pathExists hostHomePath;

      # Host-specific NixOS config path (for auto-discovery)
      hostNixosPath = hostsDir + "/${name}";
      hasHostNixos = hostsDir != null && builtins.pathExists hostNixosPath;

      # ── Build the 'host' attribute for specialArgs ──
      # host.user contains the FULL resolved user spec
      hostAttrs = spec // {
        # Replace string reference with full user spec
        user = user // {
          homeDirectory = homeDir;
        };
      };

    in
    {
      "${name}" = inputs.nixpkgs.lib.nixosSystem {
        system = spec.system;

        # ── specialArgs: 'host' is available EVERYWHERE ──
        # host.user is the FULL resolved user spec
        specialArgs = {
          inherit inputs;
          host = hostAttrs;
        }
        // spec.specialArgs;

        modules =
          # CORE NixOS modules (applied to ALL hosts)
          coreModules

          # Auto-discover host NixOS config from hostsDir/<hostname>/
          # (hardware-configuration.nix should be in the host folder)
          ++ optional hasHostNixos hostNixosPath

          # Core host configuration (user, hostname, etc.)
          ++ [
            (
              { config, pkgs, ... }:
              {
                # Hostname
                networking.hostName = spec.hostName;

                # Primary user (from user spec)
                users.users.${user.name} = {
                  isNormalUser = true;
                  home = homeDir;
                  group = user.group;
                  shell = user.shell;
                  extraGroups = user.extraGroups;
                }
                // (optionalAttrs (user.uid != null) { uid = user.uid; });

                # Auto-login (only if desktop is set)
                services.displayManager.autoLogin = mkIf (spec.autoLogin && spec.desktop != null) {
                  enable = true;
                  user = user.name;
                };
              }
            )
          ]

          # ── Home Manager Integration ──
          # Only if user has home config AND homeManager input is provided
          ++ optional (hmEnabled && homeManager != null) (
            { config, ... }:
            {
              imports = [ homeManager.nixosModules.home-manager ];

              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;

                # 'host' is available in HM modules too (with resolved user)
                extraSpecialArgs = {
                  inherit inputs;
                  host = hostAttrs;
                };

                users.${user.name} = {
                  imports =
                    if spec.isMinimal then
                      # MINIMAL: only core HM modules
                      coreHomeModules
                    else
                      # FULL: core + user directory + host directory
                      coreHomeModules ++ [ user.home.directory ] ++ optional hasHostHome hostHomePath;

                  home = {
                    username = user.name;
                    homeDirectory = homeDir;
                    stateVersion = config.system.stateVersion;
                  };
                };
              };
            }
          );
      };
    };

  # ─────────────────────────────────────────────────────────────
  # MULTI-HOST BUILDER
  # ─────────────────────────────────────────────────────────────

  mkHosts =
    {
      # Attrset of host specifications { hostname = spec; ... }
      specs,
      # Attrset of user specifications { username = spec; ... }
      users,
      ...
    }@args:
    let
      # Filter to only enabled hosts
      enabledSpecs = lib.filterAttrs (_: spec: spec.enable or true) specs;

      # Build each host
      hostConfigs = lib.mapAttrsToList (
        name: spec:
        mkHost (
          (builtins.removeAttrs args [ "specs" ])
          // {
            inherit name spec;
          }
        )
      ) enabledSpecs;
    in
    lib.foldl' (acc: cfg: acc // cfg) { } hostConfigs;

in
{
  inherit mkHost mkHosts;
}
