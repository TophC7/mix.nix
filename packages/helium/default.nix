# Based on https://github.com/nix-community/nur-combined/blob/main/repos/Ev357/pkgs/helium/default.nix
{
  lib,
  pkgs,
  ...
}:
let
  version = "0.14.7.1";
  sourceMap = {
    x86_64-linux = pkgs.fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64.AppImage";
      hash = "sha256-JPsCvue71hlyS9woHsauX5xM/2PUJ+n8VEjOFquUDno=";
    };
    aarch64-linux = pkgs.fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-arm64.AppImage";
      hash = "sha256-v3XFlPgrjSLkGiTknH9GEB4n/Xck2q+RXO0isL5Spi0=";
    };
  };
in
pkgs.appimageTools.wrapType2 rec {
  pname = "helium";
  inherit version;

  src =
    sourceMap.${pkgs.stdenv.hostPlatform.system}
      or (throw "Unsupported system: ${pkgs.stdenv.hostPlatform.system}");

  extraInstallCommands =
    let
      contents = pkgs.appimageTools.extractType2 { inherit pname version src; };
    in
    ''
      mkdir -p "$out/share/applications"
      mkdir -p "$out/share/lib/helium"
      cp -r ${contents}/opt/helium/locales "$out/share/lib/helium"
      cp -r ${contents}/usr/share/* "$out/share"
      cp "${contents}/${pname}.desktop" "$out/share/applications/"
    '';

  meta = {
    description = "Private, fast, and honest web browser based on Chromium";
    homepage = "https://github.com/imputnet/helium-chromium";
    changelog = "https://github.com/imputnet/helium-linux/releases/tag/${version}";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    license = lib.licenses.gpl3;
    mainProgram = "helium";
  };
}
