# Flake-parts module that imports all mix.nix flake-parts modules
#
# Usage:
#   imports = [ inputs.mix-nix.flakeModules.default ];
#
# This imports: hosts, secrets, modules, overlays, packages, devshell
#
# Receives mixInputs from flake.nix to forward mix.nix's inputs to consumers.
# This allows consumers to use dependencies like nix-cachyos-kernel without declaring them.
#
{ mixInputs }:
{
  imports = [
    (import ./hosts.nix { inherit mixInputs; })
    ./secrets.nix
    ./modules.nix
    (import ./overlays.nix { inherit mixInputs; })
    ./packages.nix
    ./devshell.nix
  ];
}
