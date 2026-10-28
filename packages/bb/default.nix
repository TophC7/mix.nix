# bb: self-building agent IDE, from the official Linux AppImage (x86_64 only upstream).
# electron-updater only acts when $APPIMAGE is set, which the wrapper never sets,
# so the self-updater stays inert.
{ lib, pkgs, ... }:
let
  pin = lib.importJSON ./version.json;
  inherit (pin) version;
  pname = "bb";
  src = pkgs.fetchurl {
    url = "https://github.com/get-bb/bb/releases/download/desktop-v${version}/bb-${version}-x86_64.AppImage";
    inherit (pin) hash;
  };
  contents = pkgs.appimageTools.extract { inherit pname version src; };
in
pkgs.appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 ${contents}/bb.desktop $out/share/applications/bb.desktop
    substituteInPlace $out/share/applications/bb.desktop --replace-fail 'Exec=AppRun' 'Exec=bb'
    cp -r ${contents}/usr/share/icons $out/share/
  '';

  meta = {
    description = "Agentic IDE that builds itself";
    homepage = "https://github.com/get-bb/bb";
    changelog = "https://github.com/get-bb/bb/releases/tag/desktop-v${version}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "bb";
  };
}
