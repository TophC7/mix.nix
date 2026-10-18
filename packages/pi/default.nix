{
  inputs,
  pkgs,
  ...
}:
inputs.pi.packages.${pkgs.stdenv.hostPlatform.system}.default
