# t3code - a minimal web GUI for coding agents (Codex, Claude Code)
# Upstream: https://github.com/pingdotgg/t3code
#
# Packaged from the upstream AppImage release. Only x86_64-linux is published.
{
  lib,
  pkgs,
  ...
}:
let
  version = "0.0.15";
  src = pkgs.fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
    hash = "sha256-Z8y7SWH55+ZC7cRpgo0cdG273rbDiFS3pXQt3up7sDg=";
  };
in
pkgs.appimageTools.wrapType2 rec {
  pname = "t3code";
  inherit version src;

  extraInstallCommands =
    let
      contents = pkgs.appimageTools.extractType2 { inherit pname version src; };
    in
    ''
      mkdir -p "$out/share/applications"
      cp -r ${contents}/usr/share/* "$out/share" 2>/dev/null || true
      cp "${contents}/t3-code-desktop.desktop" "$out/share/applications/${pname}.desktop"
      substituteInPlace "$out/share/applications/${pname}.desktop" \
        --replace-fail 'Exec=AppRun' 'Exec=${meta.mainProgram}'
    '';

  meta = {
    description = "Minimal web GUI for coding agents (Codex, Claude Code)";
    homepage = "https://github.com/pingdotgg/t3code";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${version}";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.mit;
    mainProgram = "t3code";
  };
}
