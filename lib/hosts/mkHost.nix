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
#   inputs          - Flake inputs (v2: inputs.self is the layout root)
#   apiVersion      - Optional: configuration API version, 1 (default, deprecated) or 2
#   homeManager     - Optional: Home Manager input
#   secrets         - Optional: secrets attrset (exposed as config.secrets.*)
#   specialArgs     - Optional: global special arguments (merged with spec.specialArgs)
#
# API v1 only (rejected in v2 when supplied, even as null/[]):
#   hostsDir        - Optional: NixOS config from hostsDir/<name>/ or <name>.nix
#   hostsHomeDir    - Optional: host HM from hostsHomeDir/<name>/ or <name>.nix
#   usersHomeDir    - Optional: user HM profile from usersHomeDir/<username>/ or <username>.nix
#   coreModules     - NixOS modules applied to all hosts
#   coreHomeModules - Home Manager modules applied to all users with HM
#
# API v2 only (rejected in v1 when supplied, even as null):
#   extends         - Optional: another layout root; names resolve here first, then
#                     there, and its core applies before this root's core
#
# API v2 layout (fixed, relative to inputs.self; <x>/ means <x>/default.nix, else <x>.nix):
#   hosts/<name>/              host NixOS; a host directory may hold home/ or home.nix,
#                              imported into the enrolled user after the profile
#   modules/core/              NixOS for every host; a core directory may hold
#                              home/ or home.nix, added to home-manager.sharedModules
#   modules/users/<username>/  HM profile; enrolls the user
#   modules/features/<name>/   nixos.nix and/or home.nix, loaded by lib.features
#
# Home Manager (the user is enrolled only when its profile is found):
#   v1 - HM integration only when the profile is found AND homeManager is set; imports
#        secrets, coreHomeModules, profile, then optional host config
#        (isMinimal keeps only secrets + coreHomeModules).
#   v2 - HM integration whenever homeManager is set; imports secrets, profile, then
#        host HM. Shared modules come from home-manager.sharedModules. v2 declares no
#        isMinimal; consumers add their own host flags via hostSpecExtensions.
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
  inherit (lib) optional optionalAttrs;

  migrationUrl = "https://github.com/tophc7/mix.nix#migrating-from-v1";

  # Version-specific builder arguments; their presence (not value) is rejected
  # under the other version
  v1OnlyArgs = [
    "coreHomeModules"
    "coreModules"
    "hostsDir"
    "hostsHomeDir"
    "usersHomeDir"
  ];
  v2OnlyArgs = [ "extends" ];

  # Auto-discovery: directory (<dir>/<name>/) before flat file (<dir>/<name>.nix)
  discover =
    dir: name:
    let
      dirPath = dir + "/${name}";
      filePath = dir + "/${name}.nix";
    in
    if dir == null then
      null
    else if builtins.pathExists dirPath then
      dirPath
    else if builtins.pathExists filePath then
      filePath
    else
      null;

  # A directory entrypoint's home/ or home.nix; flat files have none
  discoverHome =
    path: if path != null && lib.filesystem.pathIsDirectory path then discover path "home" else null;

  # ─────────────────────────────────────────────────────────────
  # PUBLIC BOUNDARY: version validation + single v1 warning
  # ─────────────────────────────────────────────────────────────
  # Applied once per mkHost / mkHosts call so a batch warns once, not per host,
  # and invalid versions/arguments fail even when no host is enabled.
  withApiVersion =
    args: result:
    let
      apiVersion = args.apiVersion or 1;
      shown = if builtins.isInt apiVersion then toString apiVersion else "a ${builtins.typeOf apiVersion}";
      supplied = builtins.filter (arg: args ? ${arg}) (if apiVersion == 2 then v1OnlyArgs else v2OnlyArgs);
    in
    if !(builtins.isInt apiVersion && (apiVersion == 1 || apiVersion == 2)) then
      throw "mix.nix: unsupported apiVersion ${shown}; supported versions are 1 (deprecated) and 2. See ${migrationUrl}"
    else if apiVersion == 2 && supplied != [ ] then
      throw "mix.nix: apiVersion = 2 does not accept ${builtins.concatStringsSep ", " supplied}. v2 uses a fixed layout under the flake root: hosts/, modules/core, modules/features/, modules/users/. See ${migrationUrl}"
    else if apiVersion == 1 && supplied != [ ] then
      throw "mix.nix: ${builtins.concatStringsSep ", " supplied} requires apiVersion = 2. See ${migrationUrl}"
    else if apiVersion == 1 then
      lib.warn "mix.nix: configuration API v1 is deprecated and a future breaking update will remove it (omitted or 1 will then fail, never silently switch to v2). After migrating, set mix.apiVersion = 2 (or apiVersion = 2 for lib.mkFlake / lib.hosts.mkHost / lib.hosts.mkHosts). See ${migrationUrl}" result
    else
      result;

  # ─────────────────────────────────────────────────────────────
  # SINGLE HOST BUILDER (unvalidated; callers go through withApiVersion)
  # ─────────────────────────────────────────────────────────────

  buildHost =
    {
      # The hostname (attrset key)
      name,
      # The evaluated host specification
      spec,
      # User definitions (attrset)
      users,
      # Inputs from the flake
      inputs,
      # Configuration API version (validated at the public boundary)
      apiVersion ? 1,
      # v1: Optional path to hosts directory for NixOS auto-discovery
      hostsDir ? null,
      # v1: Optional path to home/hosts directory for HM auto-discovery
      hostsHomeDir ? null,
      # v1: Optional path to users directory for user HM profile auto-discovery
      usersHomeDir ? null,
      # v1: CORE NixOS modules - applied to ALL hosts
      coreModules ? [ ],
      # v1: CORE Home Manager modules - applied to ALL users with HM
      coreHomeModules ? [ ],
      # v2: another layout root to fall back to
      extends ? null,
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

      # v2 layout roots, most specific first
      roots = [
        (
          if inputs ? self && inputs.self != null then
            (inputs.self.outPath or inputs.self)
          else
            throw "mix.nix: apiVersion = 2 needs inputs.self to locate hosts/ and modules/"
        )
      ] ++ optional (extends != null) extends;
      # First root providing <root>/<sub>/<name>
      findIn = sub: name: lib.findFirst (p: p != null) null (map (root: discover (root + "/${sub}") name) roots);

      # Host-specific NixOS config path (for auto-discovery)
      hostNixosPath = if apiVersion == 1 then discover hostsDir name else findIn "hosts" name;
      hasHostNixos = hostNixosPath != null;

      # v2 core: extended root first, then this root; each core directory's home/ is shared HM
      coreLayer =
        core:
        let
          coreHome = discoverHome core;
        in
        {
          imports = [ core ];
        }
        // optionalAttrs (coreHome != null && homeManager != null) {
          home-manager.sharedModules = [ coreHome ];
        };
      nixosCore =
        if apiVersion == 1 then
          coreModules
        else
          map coreLayer (lib.filter (p: p != null) (map (root: discover (root + "/modules") "core") (lib.reverseList roots)));

      # ── Home Manager ──
      # Personal profile discovered by resolved user name; enrolls the user when found
      userHomePath = if apiVersion == 1 then discover usersHomeDir user.name else findIn "modules/users" user.name;
      hasUserHome = userHomePath != null;
      # Host HM: v1 from hostsHomeDir; v2 from the host directory (home/, then home.nix)
      hostHomePath = if apiVersion == 1 then discover hostsHomeDir name else discoverHome hostNixosPath;

      # v1: only with a found profile; v2: features contribute via home-manager.sharedModules
      hmIntegrated = homeManager != null && (apiVersion == 2 || hasUserHome);

      homeImports =
        if apiVersion == 1 && spec.isMinimal or false then
          # v1 MINIMAL: only core HM modules
          coreHomeModules
        else
          # FULL: core (v1) + user profile + host config
          coreHomeModules ++ [ userHomePath ] ++ optional (hostHomePath != null) hostHomePath;

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
        # lib       - Extended lib with mix.nix utilities (v2: plus lib.features)
        specialArgs = {
          inherit inputs secrets;
          lib =
            if apiVersion == 2 then
              lib
              // {
                features = import ../features.nix { inherit lib; } {
                  featuresDirs = map (root: root + "/modules/features") roots;
                  withHome = homeManager != null;
                };
              }
            else
              lib;
          host = hostAttrs;
          hosts = specs;
        }
        // specialArgs
        // spec.specialArgs;

        modules =
          # CORE NixOS modules (applied to ALL hosts)
          nixosCore

          # Auto-discovered host NixOS config
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
              }
            )
          ]

          # ── Home Manager Integration ──
          ++ optional hmIntegrated (
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

                users = optionalAttrs hasUserHome {
                  ${user.name} = {
                    # Secrets first, then core/profile/host imports
                    imports = [ (lib.secrets.mkModule secrets) ] ++ homeImports;

                    home = {
                      username = user.name;
                      homeDirectory = homeDir;
                      stateVersion = config.system.stateVersion;
                    };
                  };
                };
              };
            }
          );
      };
    };

  # ─────────────────────────────────────────────────────────────
  # PUBLIC BUILDERS
  # ─────────────────────────────────────────────────────────────
  mkHost = args: withApiVersion args (buildHost args);

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
        buildHost (
          (builtins.removeAttrs args [ "specs" ])
          // {
            inherit name spec specs;
          }
        )
      ) enabledSpecs;
    in
    withApiVersion args (lib.foldl' (acc: cfg: acc // cfg) { } hostConfigs);

in
{
  inherit mkHost mkHosts;
}
