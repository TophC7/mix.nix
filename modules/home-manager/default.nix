# Home Manager modules index
# Auto-discovers modules and exposes them as paths (not pre-imported)
#
# Usage (individual):
#   imports = [ inputs.mix-nix.homeManagerModules.fastfetch ];
#
# Usage (all):
#   imports = [ inputs.mix-nix.homeManagerModules.default ];
#
{ lib, ... }:
let
  # Convert filename to attr name (strip .nix suffix)
  toAttrName = name: if lib.hasSuffix ".nix" name then lib.removeSuffix ".nix" name else name;

  # Build attrset of module paths from filenames
  modules = lib.listToAttrs (
    map (name: {
      name = toAttrName name;
      value = ./. + "/${name}";
    }) (lib.fs.scanNames ./.)
  );
in
modules
// {
  # Import all modules at once
  default =
    { ... }:
    {
      imports = lib.fs.scanPaths ./.;
    };
}
