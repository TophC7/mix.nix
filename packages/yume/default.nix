# Yume - Native desktop UI for Claude Code
#
# Tauri-based desktop client with orchestration, streaming,
# background agents, and multi-provider support.
#
# Usage:
#   pkgs.yume
#
{ lib, pkgs, ... }:
let
  inherit (pkgs)
    stdenv
    fetchurl
    autoPatchelfHook
    dpkg
    makeWrapper
    wrapGAppsHook3
    gtk3
    webkitgtk_4_1
    openssl
    libsoup_3
    gdk-pixbuf
    cairo
    glib
    ;

  versionInfo = lib.importJSON ./version.json;

  runtimeLibs = [
    gtk3
    webkitgtk_4_1
    openssl
    libsoup_3
    gdk-pixbuf
    cairo
    glib
    stdenv.cc.cc.lib # libstdc++ for yume-bin
  ];
in
stdenv.mkDerivation {
  pname = "yume";
  inherit (versionInfo) version;

  src = fetchurl {
    inherit (versionInfo) url hash;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = runtimeLibs;

  unpackPhase = ''
    dpkg-deb -x $src .
  '';

  installPhase = ''
    runHook preInstall

    # Binary
    install -Dm755 usr/bin/yume $out/bin/yume

    # Resources (server binary, plugins, scripts)
    mkdir -p $out/lib/yume/resources
    cp -r usr/lib/yume/resources/* $out/lib/yume/resources/

    # Icons
    for size in 32x32 128x128 "256x256@2"; do
      if [ -f "usr/share/icons/hicolor/$size/apps/yume.png" ]; then
        install -Dm644 \
          "usr/share/icons/hicolor/$size/apps/yume.png" \
          "$out/share/icons/hicolor/$size/apps/yume.png"
      fi
    done

    # Desktop entry
    install -Dm644 usr/share/applications/yume.desktop $out/share/applications/yume.desktop
    substituteInPlace $out/share/applications/yume.desktop \
      --replace-fail 'Exec=yume' "Exec=$out/bin/yume" \
      --replace-fail 'Categories=' 'Categories=Development;'

    runHook postInstall
  '';

  # Point the Tauri binary at its resources
  postFixup = ''
    wrapProgram $out/bin/yume \
      --set WEBKIT_DISABLE_COMPOSITING_MODE 1 \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}"
  '';

  meta = {
    description = "Native desktop UI for Claude Code";
    homepage = "https://github.com/aofp/yume";
    changelog = "https://github.com/aofp/yume/releases/tag/v${versionInfo.version}";
    mainProgram = "yume";
    platforms = [ "x86_64-linux" ];
  };
}
