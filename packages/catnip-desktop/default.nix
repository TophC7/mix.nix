# catnip-desktop — Electrobun native-window wrapper for W&B Catnip.
#
# Built with lib.desktop.mkElectrobunApp (url mode). Connects to a
# running Catnip instance — the service itself is deployed separately
# (Docker, systemd, Codespaces, etc.).
#
# URL is configurable via .override:
#   catnip-desktop.override { catnipUrl = "http://nimbus:6369"; }
#
{
  lib,
  pkgs,
  ...
}:
let
  mkCatnipDesktop =
    { catnipUrl ? "http://localhost:6369" }:
    lib.desktop.mkElectrobunApp pkgs {
      pname = "catnip-desktop";
      desktopName = "Catnip";
      genericName = "Coding Agent Manager";
      comment = "W&B Catnip – containerized coding agent sessions";
      identifier = "foo.ryot.catnip-desktop";
      categories = [
        "Development"
        "Utility"
      ];

      # Pinned to commit SHA — raw.githubusercontent.com/main is mutable
      icon = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/wandb/catnip/15af04e87ffe09c3861465de088e356d2fa3e2bd/public/icon-512-any.png";
        hash = "sha256-rOcOl6YBIWHKNT7+0iEkXEwNpMpW5wl5u2j3hpvCvxQ=";
      };

      url = {
        default = catnipUrl;
      };

      meta = {
        description = "Electrobun native-window wrapper for W&B Catnip";
        homepage = "https://github.com/wandb/catnip";
        license = lib.licenses.asl20;
      };
    };
in
lib.makeOverridable mkCatnipDesktop { }
