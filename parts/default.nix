# Flake-parts module that imports all mix.nix flake-parts modules
#
# Usage:
#   imports = [ inputs.mix-nix.flakeModules.default ];
#
# This imports: hosts, secrets, modules, overlays, packages, devshell
#
_: {
  imports = [
    ./hosts.nix
    ./secrets.nix
    ./modules.nix
    ./overlays.nix
    ./packages.nix
    ./devshell.nix
  ];

  # Expose all flake-parts modules for consumers
  flake.flakeModules = {
    default = ./default.nix;
    hosts = ./hosts.nix;
    secrets = ./secrets.nix;
    modules = ./modules.nix;
    overlays = ./overlays.nix;
    packages = ./packages.nix;
    devshell = ./devshell.nix;
  };
}
