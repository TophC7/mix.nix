# Feature loader (API v2 hosts only)
# mkHost binds it to each layout root's modules/features (local root first, then
# the extended root) and exposes it to host modules as lib.features.
# Turns a list of features into NixOS modules, one per directory.
#
# Each feature directory offers nixos.nix, home.nix, or both:
#   nixos.nix -> imported into the NixOS configuration
#   home.nix  -> passed by path to home-manager.sharedModules; ignored when the host
#                has no Home Manager (mix.homeManager = null), like every other HM part
# System-only features declare no home-manager option.
#
# Each entry resolves in order:
#   1. a string naming a feature in the first features dir that has it ("audio", "pangolin/newt")
#   2. otherwise the entry itself as a directory (./local, "${inputs.x}/feature")
#
# Usage:
#   imports = lib.features [ "audio" "pangolin/newt" ./local-feature ];
{ lib }:
{ featuresDirs, withHome }:
let
  isFeature = dir: builtins.pathExists (dir + "/nixos.nix") || builtins.pathExists (dir + "/home.nix");

  resolve =
    entry:
    let
      isNamed = builtins.isString entry && !lib.hasPrefix "/" entry;
      named =
        if isNamed then
          lib.findFirst isFeature null (map (dir: dir + "/${entry}") featuresDirs)
        else
          null;
      entryStr = if builtins.isAttrs entry then "(attribute set)" else toString entry;
    in
    if named != null then
      named
    else if builtins.isPath entry || (builtins.isString entry && lib.hasPrefix "/" entry) then
      entry
    else
      throw "lib.features: unknown feature \"${entryStr}\" in ${lib.concatMapStringsSep ", " toString featuresDirs}";
in
map (
  entry:
  let
    dir = resolve entry;
    nixos = dir + "/nixos.nix";
    home = dir + "/home.nix";
  in
  if !(isFeature dir) then
    throw "lib.features: ${toString dir} has neither nixos.nix nor home.nix"
  else
    {
      _file = toString dir;
      imports = lib.optional (builtins.pathExists nixos) nixos;
    }
    // lib.optionalAttrs (withHome && builtins.pathExists home) { home-manager.sharedModules = [ home ]; }
)
