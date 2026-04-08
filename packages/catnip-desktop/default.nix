# catnip-desktop — Electrobun native-window wrapper for W&B Catnip.
#
# Built with lib.desktop.mkElectrobunApp (url mode). Connects to a
# running Catnip instance — the service itself is deployed separately
# (Docker, systemd, Codespaces, etc.).
{
  lib,
  pkgs,
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

  url = {
    default = "http://localhost:6369";
    # Override at runtime: CATNIP_DESKTOP_URL=http://my-server:6369
  };

  meta = {
    description = "Electrobun native-window wrapper for W&B Catnip";
    homepage = "https://github.com/wandb/catnip";
    license = lib.licenses.asl20;
  };
}
