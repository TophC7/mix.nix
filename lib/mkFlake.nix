# Standalone flake builder for non-flake-parts users
#
# Provides the same functionality as the flake-parts modules (mix.hosts, mix.secrets)
# but as a simple function that returns flake outputs.
#
# Usage (API v2; fixed layout under inputs.self: hosts/, modules/core,
# modules/features/, modules/users/):
#   outputs = { nixpkgs, mix-nix, home-manager, ... }@inputs:
#     mix-nix.lib.mkFlake {
#       apiVersion = 2;
#       inherit inputs;
#       homeManager = home-manager;
#
#       users.toph = {
#         name = "toph";
#         shell = "fish";
#       };
#
#       hosts.desktop = {
#         user = "toph";
#         desktop = "niri";
#       };
#     };
#
# API v1 is the default when apiVersion is omitted (deprecated; emits one warning).
# Its locations (coreModules, coreHomeModules, hostsDir, hostsHomeDir, usersHomeDir)
# are rejected by v2 when passed, even [ ]/null. extends is v2-only; v1 rejects it
# when passed, even null.
# A future breaking update will remove v1; omitted/1 will then fail with migration guidance.
#
# Returns:
#   { nixosConfigurations = { desktop = <nixosSystem>; ... }; }
#
{ lib }:

{
  mkFlake =
    {
      # Required: flake inputs (must include nixpkgs)
      inputs,

      # Required: user specifications
      # { username = { name, shell, ... }; }
      users,

      # Required: host specifications
      # { hostname = { user, desktop?, system?, ... }; }
      hosts,

      # Optional: secrets configuration
      # { file = ./secrets.nix; gitattributes = ./.gitattributes; }
      secrets ? { },

      # Optional: configuration API version (1 default/deprecated, 2 current);
      # validated by lib.hosts.mkHosts
      apiVersion ? 1,

      # Optional, API v1 only: NixOS modules applied to all hosts (v2: modules/core)
      coreModules ? [ ],

      # Optional, API v1 only: Home Manager modules applied to all users with HM
      coreHomeModules ? [ ],

      # Optional, API v1 only: directory for per-host NixOS configs (v2: hosts/)
      hostsDir ? null,

      # Optional, API v1 only: directory for per-host Home Manager configs
      # (v2: hosts/<host>/home/ or home.nix)
      hostsHomeDir ? null,

      # Optional, API v1 only: directory for per-user Home Manager profiles
      # (v2: modules/users/)
      usersHomeDir ? null,

      # Optional, API v2 only: another layout root to fall back to
      extends ? null,

      # Optional: Home Manager input (v1: HM integration only for users with a profile;
      # v2: loads HM integration for all hosts when non-null)
      homeManager ? inputs.home-manager or null,
    }@args:
    let
      # Load secrets if configured
      loadedSecrets =
        if secrets ? file && secrets.file != null then
          lib.secrets.load {
            path = secrets.file;
            gitattributes = secrets.gitattributes or null;
            pattern = secrets.pattern or "secrets.nix";
            skipValidation = secrets.skipValidation or false;
          }
        else
          { };

    in
    {
      # Generate nixosConfigurations from specs
      nixosConfigurations = lib.hosts.mkHosts (
        {
          specs = hosts;
          inherit
            apiVersion
            inputs
            users
            homeManager
            ;
          secrets = loadedSecrets;
        }
        # Forward version-specific args only when explicitly passed (defaults above are
        # documentation), so the other version rejects even explicit [ ]/null.
        // builtins.intersectAttrs {
          coreModules = null;
          coreHomeModules = null;
          hostsDir = null;
          hostsHomeDir = null;
          usersHomeDir = null;
          extends = null;
        } args
      );
    };
}
