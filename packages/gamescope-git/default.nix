# Gamescope-git - Latest development version of Valve's gamescope
#
# Gamescope is a micro-compositor for Steam gaming sessions, providing:
# - HDR support
# - Frame limiting and VRR
# - Resolution scaling
# - AMD FSR integration
#
# Usage:
#   pkgs.gamescope-git      - Full compositor
#   pkgs.gamescope-git.wsi  - WSI layer only (for embedding)
#
{ lib, pkgs, ... }:
let
  inherit (pkgs) fetchFromGitHub;

  versionInfo = lib.importJSON ./version.json;
  shortRev = builtins.substring 0 7 versionInfo.rev;

  # Shared source for both variants
  src = fetchFromGitHub {
    owner = "ValveSoftware";
    repo = "gamescope";
    rev = versionInfo.rev;
    hash = versionInfo.hash;
    fetchSubmodules = true;
  };

  # Factory for creating git variants
  mkGamescopeGit =
    {
      base,
      pname,
      description,
    }:
    base.overrideAttrs (prevAttrs: {
      inherit pname src;
      version = versionInfo.version;

      postPatch = (prevAttrs.postPatch or "") + ''
        # Inject git rev into WSI layer identification
        substituteInPlace layer/VkLayer_FROG_gamescope_wsi.cpp \
          --replace-fail 'WSI] Surface' 'WSI ${shortRev}] Surface'

        # Inject version into meson build
        substituteInPlace src/meson.build \
          --replace-fail "'git', 'describe', '--always', '--tags', '--dirty=+'" "'echo', '${versionInfo.rev}'"

        patchShebangs default_extras_install.sh
      '';

      meta = (prevAttrs.meta or { }) // {
        inherit description;
      };
    });

  # Full gamescope compositor
  gamescope = mkGamescopeGit {
    base = pkgs.gamescope;
    pname = "gamescope-git";
    description = "Gamescope compositor (git version)";
  };

  # WSI layer only (for embedding in other compositors)
  wsi = mkGamescopeGit {
    base = pkgs.gamescope-wsi;
    pname = "gamescope-wsi-git";
    description = "Gamescope WSI layer (git version)";
  };
in
# Export full gamescope as default, with wsi as attribute
gamescope // { inherit wsi; }
