# Home Manager modules index
# All modules are auto-discovered and exposed as individual attributes
#
# Usage (individual):
#   imports = [ inputs.lib-nix.homeManagerModules.colors ];
#
# Usage (all at once):
#   imports = [ inputs.lib-nix.homeManagerModules.default ];
{ inputs, lib, ... }:

# Auto-discover all modules as named attributes + default for importing all
lib.fs.scanModules ./. { inherit inputs; }
// {
  default =
    { ... }:
    {
      imports = lib.fs.scanPaths ./.;
    };
}
