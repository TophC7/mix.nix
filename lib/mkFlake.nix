# Standalone flake builder for non-flake-parts users
#
# Provides the same functionality as the flake-parts modules (mix.hosts, mix.secrets)
# but as a simple function that returns flake outputs.
#
# Usage:
#   outputs = { nixpkgs, mix-nix, home-manager, ... }@inputs:
#     mix-nix.lib.mkFlake {
#       inherit inputs;
#       homeManager = home-manager;
#
#       users.toph = {
#         name = "toph";
#         shell = pkgs.fish;
#         home.directory = ./home/users/toph;
#       };
#
#       hosts.desktop = {
#         user = "toph";
#         desktop = "niri";
#       };
#     };
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
      # { username = { name, shell, home?, ... }; }
      users,

      # Required: host specifications
      # { hostname = { user, desktop?, system?, ... }; }
      hosts,

      # Optional: secrets configuration
      # { file = ./secrets.nix; gitattributes = ./.gitattributes; }
      secrets ? { },

      # Optional: NixOS modules applied to all hosts
      coreModules ? [ ],

      # Optional: Home Manager modules applied to all users with HM
      coreHomeModules ? [ ],

      # Optional: directory for per-host NixOS configs
      hostsDir ? null,

      # Optional: directory for per-host Home Manager configs
      hostsHomeDir ? null,

      # Optional: Home Manager input (required for HM integration)
      homeManager ? inputs.home-manager or null,
    }:
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
      nixosConfigurations = lib.hosts.mkHosts {
        specs = hosts;
        inherit
          inputs
          users
          coreModules
          coreHomeModules
          hostsDir
          hostsHomeDir
          homeManager
          ;
        secrets = loadedSecrets;
      };
    };
}
