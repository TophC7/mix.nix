# catnip-desktop — Electrobun native-window wrapper for W&B Catnip.
#
# Built with lib.desktop.mkElectrobunApp (command mode). Spawns `catnip serve`
# from the current working directory, waits for HTTP readiness, then opens a
# system-webview window.
#
# Usage:
#   cd /path/to/my/repo && catnip-desktop
#
{
  lib,
  pkgs,
  catnip ? import ../catnip { inherit lib pkgs; },
  ...
}:
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

  command = {
    package = catnip;
    binName = "catnip";
    args = [
      "serve"
      "--port"
      "{port}"
    ];
    defaultPort = 6369;
  };

  meta = {
    description = "Electrobun native-window wrapper for W&B Catnip";
    homepage = "https://github.com/wandb/catnip";
    license = lib.licenses.asl20;
  };
}
