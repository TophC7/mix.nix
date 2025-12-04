# Home Manager modules index
# All modules are auto-discovered and exposed as paths
#
# Usage (individual):
#   imports = [ inputs.mix-nix.homeManagerModules.fastfetch ];
#
# Usage (all at once):
#   imports = [ inputs.mix-nix.homeManagerModules.default ];
{ lib, ... }:

lib.fs.scanAttrs ./.
// {
  default =
    { ... }:
    {
      imports = lib.fs.scanPaths ./.;
    };
}
