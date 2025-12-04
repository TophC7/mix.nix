# NixOS modules index
# All modules are auto-discovered and exposed as paths
#
# Usage (individual):
#   imports = [ inputs.mix-nix.nixosModules.oci-stacks ];
#
# Usage (all at once):
#   imports = [ inputs.mix-nix.nixosModules.default ];
#
# Note: Modules using lib.infra.* require the extended lib via specialArgs
{ lib, ... }:

lib.fs.scanAttrs ./.
// {
  default =
    { ... }:
    {
      imports = lib.fs.scanPaths ./.;
    };
}
