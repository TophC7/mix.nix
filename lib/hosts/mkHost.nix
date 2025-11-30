# Host builder functions
# Transforms host/user specifications into nixosConfigurations
#
# mkHost  - Build a single host configuration
# mkHosts - Build multiple host configurations from specs attrset
#
# Arguments (mkHost):
#   name            - Hostname
#   spec            - Host specification (from lib.hosts.types.hostSpec)
#   users           - User specifications attrset
#   inputs          - Flake inputs
#   hostsDir        - Optional: auto-discover NixOS config from hostsDir/<name>/
#   hostsHomeDir    - Optional: auto-discover HM config from hostsHomeDir/<name>/
#   coreModules     - NixOS modules applied to all hosts
#   coreHomeModules - Home Manager modules applied to all users with HM
#   homeManager     - Home Manager input (enables HM integration)
#   secrets         - Optional: secrets attrset (exposed as config.secrets.*)
#
# Arguments (mkHosts):
#   specs           - Attrset of host specifications { hostname = spec; }
#   users           - Attrset of user specifications { username = spec; }
#   (plus all optional args from mkHost)
#
# Returns:
#   Attrset of nixosConfigurations { hostname = nixosSystem; }
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
      # Optional: Secrets (git-crypt encrypted, freeform attrset)
      secrets ? { },
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

        # ── specialArgs: 'host' and 'secrets' available EVERYWHERE ──
        # host.user is the FULL resolved user spec
        specialArgs = {
          inherit inputs secrets;
          host = hostAttrs;
        }
        // spec.specialArgs;

        modules =
          # CORE NixOS modules (applied to ALL hosts)
          coreModules

          # Auto-discover host NixOS config from hostsDir/<hostname>/
          # (hardware-configuration.nix should be in the host folder)
          ++ optional hasHostNixos hostNixosPath

          # Secrets module - makes config.secrets.* available
          ++ [ (lib.secrets.mkModule secrets) ]

          # Core host configuration (user, hostname, etc.)
          ++ [
            (
              { ... }:
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

                # 'host' and 'secrets' available in HM modules too
                extraSpecialArgs = {
                  inherit inputs secrets;
                  host = hostAttrs;
                };

                users.${user.name} = {
                  imports =
                    # Secrets module for Home Manager
                    [ (lib.secrets.mkModule secrets) ]
                    ++ (
                      if spec.isMinimal then
                        # MINIMAL: only core HM modules
                        coreHomeModules
                      else
                        # FULL: core + user directory + host directory
                        coreHomeModules ++ [ user.home.directory ] ++ optional hasHostHome hostHomePath
                    );

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
