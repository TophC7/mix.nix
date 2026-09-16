{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  omp = inputs.omp;
  upstreamPackage = omp.packages.${system}.default;
in
upstreamPackage.overrideAttrs (old: {
  bunInstallFlags = lib.unique ((old.bunInstallFlags or [ ]) ++ [ "--offline" ]);
})
