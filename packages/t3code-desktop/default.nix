# t3code-desktop — Electrobun native-window wrapper around the t3code CLI.
#
# Built with lib.desktop.mkElectrobunApp (command mode). Spawns `t3` as a
# child process, waits for HTTP readiness, then opens a system-webview window.
{
  lib,
  pkgs,
  t3code ? import ../t3code { inherit lib pkgs; },
  ...
}:
lib.desktop.mkElectrobunApp pkgs {
  pname = "t3code-desktop";
  desktopName = "T3 Code";
  genericName = "Coding Agent UI";
  comment = "Minimal web GUI for coding agents (Codex, Claude Code)";
  identifier = "foo.ryot.t3code-desktop";
  categories = [
    "Development"
    "Utility"
  ];

  # Icon follows t3code's source rev — no separate fetchurl/hash to maintain
  icon = "${t3code.src}/assets/prod/black-universal-1024.png";

  command = {
    package = t3code;
    binName = "t3";
    args = [
      "--no-browser"
      "--port"
      "{port}"
      "--host"
      "{host}"
    ];
    defaultPort = 18822;
  };

  meta = {
    description = "Electrobun native-window wrapper around t3code";
    homepage = "https://github.com/pingdotgg/t3code";
    changelog = "https://github.com/pingdotgg/t3code/commits/main";
    license = lib.licenses.mit;
  };
}
