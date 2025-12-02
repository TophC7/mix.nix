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
#   hostsDir        - Optional: auto-discover NixOS config from hostsDir/<name>/ or <name>.nix
#   hostsHomeDir    - Optional: auto-discover HM config from hostsHomeDir/<name>/ or <name>.nix
#   usersHomeDir    - Optional: auto-discover user HM config from usersHomeDir/<username>/ or <username>.nix
#   coreModules     - NixOS modules applied to all hosts
#   coreHomeModules - Home Manager modules applied to all users with HM
#   homeManager     - Home Manager input (enables HM integration)
#   secrets         - Optional: secrets attrset (exposed as config.secrets.*)
#   specialArgs     - Optional: global special arguments (merged with spec.specialArgs)
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
      # Optional: path to home/users directory for user HM auto-discovery
      usersHomeDir ? null,
      # CORE NixOS modules - applied to ALL hosts
      coreModules ? [ ],
      # CORE Home Manager modules - applied to ALL users with HM
      coreHomeModules ? [ ],
      # Optional: Home Manager input
      homeManager ? null,
      # Optional: Secrets (git-crypt encrypted, freeform attrset)
      secrets ? { },
      # Optional: Global special arguments (merged with spec.specialArgs)
      specialArgs ? { },
      # Optional: All host specs (for cross-host lookups like VPN peer discovery)
      specs ? { },
    }:
    let
      # ── Resolve user from reference ──
      user =
        users.${spec.user}
          or (throw "Host '${name}' references unknown user '${spec.user}'. Available users: ${builtins.concatStringsSep ", " (builtins.attrNames users)}");

      # Home directory path
      homeDir = "/home/${user.name}";

      # User-specific home config path (for auto-discovery)
      # Supports both directory (home/users/<username>/) and flat file (home/users/<username>.nix)
      userHomePath =
        let
          dirPath = usersHomeDir + "/${user.name}";
          filePath = usersHomeDir + "/${user.name}.nix";
        in
        if usersHomeDir == null then null
        else if builtins.pathExists dirPath then dirPath
        else if builtins.pathExists filePath then filePath
        else null;
      hasUserHome = userHomePath != null;

      # Home Manager enabled only if user home config exists
      hmEnabled = hasUserHome;

      # Host-specific NixOS config path (for auto-discovery)
      # Supports both directory (hosts/<name>/) and flat file (hosts/<name>.nix)
      hostNixosPath =
        let
          dirPath = hostsDir + "/${name}";
          filePath = hostsDir + "/${name}.nix";
        in
        if hostsDir == null then null
        else if builtins.pathExists dirPath then dirPath
        else if builtins.pathExists filePath then filePath
        else null;
      hasHostNixos = hostNixosPath != null;

      # Host-specific home config path (for auto-discovery)
      # Supports both directory (home/hosts/<name>/) and flat file (home/hosts/<name>.nix)
      hostHomePath =
        let
          dirPath = hostsHomeDir + "/${name}";
          filePath = hostsHomeDir + "/${name}.nix";
        in
        if hostsHomeDir == null then null
        else if builtins.pathExists dirPath then dirPath
        else if builtins.pathExists filePath then filePath
        else null;
      hasHostHome = hostHomePath != null;

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

        # ── specialArgs: 'host', 'hosts', 'secrets', and extended 'lib' available EVERYWHERE ──
        # host      - Current host's spec (with resolved user)
        # hosts     - All host specs (for cross-host lookups like VPN peer discovery)
        # lib       - Extended lib with mix.nix utilities
        specialArgs = {
          inherit inputs secrets lib;
          host = hostAttrs;
          hosts = specs;
        }
        // specialArgs
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
              { pkgs, ... }:
              {
                # Apply mix.nix overlay (provides pkgs.matugen, pkgs.stable.*, pkgs.eden, etc.)
                nixpkgs.overlays = [ (import ../../overlays { inherit inputs; }) ];

                # Hostname
                networking.hostName = spec.hostName;

                # Primary user (from user spec)
                # shell can be a package or string (resolved via pkgs)
                users.users.${user.name} = {
                  isNormalUser = true;
                  home = homeDir;
                  group = user.group;
                  shell = if builtins.isString user.shell then pkgs.${user.shell} else user.shell;
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
            { config, pkgs, ... }:
            let
              # Resolve shell string to package (e.g., "fish" -> pkgs.fish)
              resolveShell = shell: if builtins.isString shell then pkgs.${shell} else shell;
            in
            {
              imports = [ homeManager.nixosModules.home-manager ];

              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;

                extraSpecialArgs = {
                  inherit inputs secrets;
                  # host.user.shell is resolved to a package here
                  host = hostAttrs // {
                    user = hostAttrs.user // {
                      shell = resolveShell hostAttrs.user.shell;
                    };
                  };
                  hosts = specs;
                }
                // specialArgs
                // spec.specialArgs;

                users.${user.name} = {
                  imports = [
                    (lib.secrets.mkModule secrets)
                  ]
                  ++ (
                    if spec.isMinimal then
                      # MINIMAL: only core HM modules
                      coreHomeModules
                    else
                      # FULL: core + user config + host config
                      coreHomeModules ++ [ userHomePath ] ++ optional hasHostHome hostHomePath
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

      # Build each host (pass specs through for cross-host lookups)
      hostConfigs = lib.mapAttrsToList (
        name: spec:
        mkHost (
          (builtins.removeAttrs args [ "specs" ])
          // {
            inherit name spec specs;
          }
        )
      ) enabledSpecs;
    in
    lib.foldl' (acc: cfg: acc // cfg) { } hostConfigs;

in
{
  inherit mkHost mkHosts;
}
