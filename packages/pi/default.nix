{
  inputs,
  pkgs,
  ...
}:
pkgs.callPackage ./package.nix { source = inputs.pi; }
