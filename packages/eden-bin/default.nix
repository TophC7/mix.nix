# Eden from the official PGO AppImage: no compile, just extract and wrap.
# Source-built variant lives in packages/eden.
{ pkgs, ... }:
let
  inherit (pkgs)
    stdenv
    fetchurl
    dwarfs
    buildFHSEnv
    makeDesktopItem
    copyDesktopItems
    ;

  pin = builtins.fromJSON (builtins.readFile ./version.json);
  inherit (pin) version;

  src = fetchurl {
    url = "https://stable.eden-emu.dev/v${version}/Eden-Linux-v${version}-amd64-clang-pgo.AppImage";
    inherit (pin) hash;
  };

  # Eden's AppImage payload is DwarFS, not SquashFS, so appimageTools can't unpack it.
  extracted = stdenv.mkDerivation {
    pname = "eden-bin-extracted";
    inherit version src;
    nativeBuildInputs = [ dwarfs ];
    dontUnpack = true;
    dontFixup = true; # bundled sharun loader must stay untouched
    installPhase = ''
      mkdir -p $out
      dwarfsextract -i $src -o $out
    '';
  };

  # The bundle ships its own libs; the FHS env supplies host GPU drivers and sockets.
  fhs = buildFHSEnv {
    name = "eden";
    targetPkgs =
      p: with p; [
        alsa-lib
        fontconfig
        freetype
        libGL
        libpulseaudio
        openssl
        udev
        vulkan-loader
        libx11
        libxcursor
        libxext
        libxi
        libxinerama
        libxrandr
        libxrender
        zlib
      ];
    runScript = "${extracted}/AppRun";
  };
in
stdenv.mkDerivation {
  pname = "eden-bin";
  inherit version;

  dontUnpack = true;
  nativeBuildInputs = [ copyDesktopItems ];

  desktopItems = [
    (makeDesktopItem {
      name = "dev.eden_emu.eden";
      exec = "eden %F";
      icon = "dev.eden_emu.eden";
      desktopName = "Eden";
      genericName = "Nintendo Switch Emulator";
      comment = "An experimental Nintendo Switch emulator";
      categories = [
        "Game"
        "Emulator"
      ];
      startupWMClass = "dev.eden_emu.eden";
      mimeTypes = [
        "application/x-nx-nca"
        "application/x-nx-nro"
        "application/x-nx-nso"
        "application/x-nx-nsp"
        "application/x-nx-xci"
      ];
    })
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/icons/hicolor/scalable/apps
    ln -s ${fhs}/bin/eden $out/bin/eden
    cp ${extracted}/dev.eden_emu.eden.svg $out/share/icons/hicolor/scalable/apps/
    runHook postInstall
  '';

  meta = {
    description = "Nintendo Switch video game console emulator (official prebuilt AppImage)";
    homepage = "https://eden-emu.dev/";
    downloadPage = "https://git.eden-emu.dev/eden-emu/eden/releases";
    mainProgram = "eden";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
  };
}
