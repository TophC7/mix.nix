# Orca: agent orchestration IDE, from the official .deb.
# Named orca-ide like upstream, avoiding GNOME's orca screen reader.
#
# The bundle carries prebuilt native helpers (node-pty, watcher, ripgrep, a daemon
# copied out to the user's data dir), so it runs inside an FHS env rather than
# patching every ELF. Two entrypoints share that env:
#   orca-ide-app  the desktop app
#   orca-ide      the CLI agents use to drive Orca (upstream's PATH command)
{ lib, pkgs, ... }:
let
  inherit (pkgs)
    stdenv
    fetchurl
    dpkg
    buildFHSEnv
    appimageTools
    writeShellScript
    makeDesktopItem
    copyDesktopItems
    makeWrapper
    ;

  pin = lib.importJSON ./version.json;
  inherit (pin) version;
  inherit (stdenv.hostPlatform) system;
  debArch =
    {
      x86_64-linux = "amd64";
      aarch64-linux = "arm64";
    }
    .${system} or (throw "orca-ide: unsupported system ${system}");

  extracted = stdenv.mkDerivation {
    pname = "orca-ide-extracted";
    inherit version;
    src = fetchurl {
      url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-ide_${version}_${debArch}.deb";
      hash = pin.hashes.${system};
    };
    nativeBuildInputs = [ dpkg ];
    dontFixup = true; # bundled binaries run inside the FHS env, untouched
    unpackPhase = "dpkg-deb -x $src .";
    # Without package-type, electron-updater falls back to its AppImage updater,
    # which stays inactive outside an AppImage instead of trying to dpkg-install.
    installPhase = ''
      mkdir -p $out
      cp -r opt usr/share $out/
      rm $out/opt/Orca/resources/package-type
    '';
  };

  app = "${extracted}/opt/Orca";

  fhs = buildFHSEnv (
    appimageTools.defaultFhsEnvArgs
    // {
      name = "orca-ide-fhs";
      targetPkgs =
        p:
        appimageTools.defaultFhsEnvArgs.targetPkgs p
        ++ (with p; [
          git
          xdg-utils
          libsecret
          libnotify
          libappindicator-gtk3
          # Linux computer use: runtime.py drives AT-SPI through python3-gi.
          (python3.withPackages (ps: [ ps.pygobject3 ]))
          gobject-introspection
          at-spi2-core
          xdotool
          xclip
          xvfb
        ]);
      runScript = writeShellScript "orca-ide-run" ''exec "$@"'';
    }
  );
in
stdenv.mkDerivation {
  pname = "orca-ide";
  inherit version;

  dontUnpack = true;
  nativeBuildInputs = [
    copyDesktopItems
    makeWrapper
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "orca-ide";
      desktopName = "Orca";
      comment = "Next-gen IDE for parallel agentic development";
      exec = "orca-ide-app %U";
      icon = "orca-ide";
      startupWMClass = "orca";
      categories = [ "Development" ];
      mimeTypes = [
        "text/markdown"
        "text/csv"
        "text/tab-separated-values"
        "x-scheme-handler/orca"
      ];
    })
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share
    cp -r ${extracted}/share/icons $out/share/
    makeWrapper ${fhs}/bin/orca-ide-fhs $out/bin/orca-ide-app --add-flags ${app}/orca-ide
    makeWrapper ${fhs}/bin/orca-ide-fhs $out/bin/orca-ide --add-flags ${app}/resources/bin/orca-ide
    runHook postInstall
  '';

  passthru = { inherit extracted fhs; };

  meta = {
    description = "Orchestrator for running coding agents side by side in parallel worktrees";
    homepage = "https://github.com/stablyai/orca";
    changelog = "https://github.com/stablyai/orca/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames pin.hashes;
    mainProgram = "orca-ide-app";
  };
}
