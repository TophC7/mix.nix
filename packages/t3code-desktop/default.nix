# t3code-desktop - Electrobun native-window wrapper around the t3code CLI.
#
# Spawns `t3` as a child of a small Bun shell app, then opens an Electrobun
# window (system webview, no CEF) pointed at the local server. See
# shell/src/bun/index.ts for why HTTP readiness > TCP readiness and why
# child cleanup goes through a kernel-level pdeath-exec shim rather than
# JS signal handlers.
{
  lib,
  pkgs,
  # Sibling package, overridable via callPackage. Default preserves
  # auto-discovery behavior when imported through `lib.fs.importAttrs`.
  t3code ? import ../t3code { inherit lib pkgs; },
  ...
}:
let
  inherit (pkgs) stdenv stdenvNoCC fetchurl;

  versionInfo = lib.importJSON ./version.json;

  # Prebuilt Electrobun binaries from upstream GH releases; keeps the main
  # build hermetic (electrobun's own wrapper would download them at runtime).
  electrobunCli = fetchurl {
    url = "https://github.com/blackboardsh/electrobun/releases/download/v${versionInfo.electrobun.version}/electrobun-cli-linux-x64.tar.gz";
    hash = versionInfo.electrobun.cliHash;
  };
  electrobunCore = fetchurl {
    url = "https://github.com/blackboardsh/electrobun/releases/download/v${versionInfo.electrobun.version}/electrobun-core-linux-x64.tar.gz";
    hash = versionInfo.electrobun.coreHash;
  };

  # prctl(PR_SET_PDEATHSIG, SIGTERM) then execvp -- see header.
  pdeathExec = pkgs.writeCBin "pdeath-exec" ''
    #define _GNU_SOURCE
    #include <sys/prctl.h>
    #include <signal.h>
    #include <unistd.h>
    #include <stdio.h>

    int main(int argc, char *argv[]) {
        if (argc < 2) {
            fprintf(stderr, "usage: pdeath-exec <cmd> [args...]\n");
            return 1;
        }
        if (prctl(PR_SET_PDEATHSIG, SIGTERM, 0, 0, 0) == -1) {
            perror("prctl(PR_SET_PDEATHSIG)");
            return 1;
        }
        execvp(argv[1], argv + 1);
        perror("execvp");
        return 127;
    }
  '';

  # StartupWMClass must match what Electrobun sets as the window class so
  # desktop environments group taskbar entries / pin launches correctly.
  desktopItem = pkgs.makeDesktopItem {
    name = "t3code-desktop";
    desktopName = "T3 Code";
    genericName = "Coding Agent UI";
    comment = "Minimal web GUI for coding agents (Codex, Claude Code)";
    exec = "t3code-desktop";
    icon = "t3code-desktop";
    startupWMClass = "t3code-desktop";
    categories = [
      "Development"
      "Utility"
    ];
    startupNotify = true;
    terminal = false;
  };

  # Runtime libs for the Electrobun launcher + libNativeWrapper.so on
  # Linux. system-webview (no CEF) needs webkit2gtk-4.1 + its GTK stack.
  runtimeLibs = with pkgs; [
    webkitgtk_4_1
    gtk3
    glib
    libsoup_3
    cairo
    pango
    gdk-pixbuf
    atk
    harfbuzz
    libxkbcommon
    libayatana-appindicator
    stdenv.cc.cc.lib
  ];

  shellSrc = ./shell;

  # FoD for the shell project's deps (electrobun + its transitives). Same
  # pattern as packages/t3code: bun install with network access, hash-pinned.
  bunDeps = stdenvNoCC.mkDerivation {
    pname = "t3code-desktop-bun-deps";
    version = "0.0.1";
    src = shellSrc;

    nativeBuildInputs = [
      pkgs.bun
      pkgs.cacert
    ];

    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall

      export HOME=$(mktemp -d)
      export BUN_INSTALL="$HOME/.bun"

      bun install --frozen-lockfile --ignore-scripts --linker=hoisted

      mkdir -p $out
      cp -a node_modules "$out/node_modules"

      runHook postInstall
    '';

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = versionInfo.bunDepsHash;
  };
in
stdenv.mkDerivation {
  pname = "t3code-desktop";
  version = "0.0.1";

  src = shellSrc;

  nativeBuildInputs = [
    pkgs.bun
    pkgs.nodejs_24
    pkgs.zstd # for extracting the stable-build .tar.zst artifact
    pkgs.makeBinaryWrapper
    pkgs.autoPatchelfHook
    pkgs.imagemagick # for resizing icons to standard hicolor sizes
  ];

  buildInputs = runtimeLibs;

  # libcef.so is only dlopen'd when using the CEF renderer; we set
  # bundleCEF: false in electrobun.config.ts so it's never loaded.
  autoPatchelfIgnoreMissingDeps = [ "libcef.so" ];

  postPatch = ''
    cp -a ${bunDeps}/node_modules ./node_modules
    chmod -R u+w ./node_modules

    # CLI under node_modules/electrobun/bin/ (where the cjs wrapper looks
    # for it, skipping its download path). Core runtime (bun, launcher,
    # libNativeWrapper.so, api/) under dist-linux-x64/.
    mkdir -p node_modules/electrobun/bin node_modules/electrobun/dist-linux-x64
    tar -xzf ${electrobunCli} -C node_modules/electrobun/bin
    tar -xzf ${electrobunCore} -C node_modules/electrobun/dist-linux-x64

    patchShebangs node_modules

    # We invoke the Electrobun CLI during buildPhase, so its ELF binaries
    # must be runnable before the fixup-time autoPatchelfHook runs.
    autoPatchelf \
      node_modules/electrobun/bin \
      node_modules/electrobun/dist-linux-x64
  '';

  buildPhase = ''
    runHook preBuild

    export HOME=$(mktemp -d)

    # Must be --env=stable (not --env stable -- the CLI silently falls
    # back to "dev"). Emits a .tar.zst under artifacts/ alongside a
    # self-extracting installer under build/ that we don't ship.
    ./node_modules/electrobun/bin/electrobun build --env=stable

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/t3code-desktop/app"
    tar --zstd -xf artifacts/stable-linux-x64-t3code-desktop.tar.zst \
      -C "$out/share/t3code-desktop/app" --strip-components=1

    # Re-patch the bun binary + libNativeWrapper.so from the tarball;
    # their DT_NEEDED entries still reference Ubuntu paths.
    autoPatchelf "$out/share/t3code-desktop/app/bin"

    # libNativeWrapper.so ships with the WM_CLASS ("ElectrobunKitchenSink-dev")
    # of Electrobun's own example app hardcoded into its .rodata -- it's
    # passed to gtk_window_set_wmclass() at window creation time, which is
    # what Wayland compositors read as app_id and what .desktop-file icon
    # matching keys off of. Overwrite the string in place with our actual
    # identifier (padded with NULs so byte-length is preserved, leaving
    # surrounding pointer offsets undisturbed).
    libWrapper="$out/share/t3code-desktop/app/bin/libNativeWrapper.so"
    chmod u+w "$libWrapper"
    offset=$(grep -abo 'ElectrobunKitchenSink-dev' "$libWrapper" | head -1 | cut -d: -f1)
    if [ -z "$offset" ]; then
      echo "error: libNativeWrapper.so no longer contains the hardcoded WM_CLASS string;" >&2
      echo "       upstream Electrobun may have fixed the bug -- drop this patch." >&2
      exit 1
    fi
    printf 't3code-desktop\0\0\0\0\0\0\0\0\0\0\0' \
      | dd of="$libWrapper" bs=1 seek="$offset" count=25 conv=notrunc status=none

    # Icon pulled from t3code's own source tree so it follows its rev
    # automatically -- no separate fetchurl/hash to maintain.
    # Install at standard hicolor sizes -- many DEs skip 1024x1024.
    local src_icon="${t3code.src}/assets/prod/black-universal-1024.png"
    for size in 16 24 32 48 64 128 256 512; do
      install -Dm644 /dev/null "$out/share/icons/hicolor/''${size}x''${size}/apps/t3code-desktop.png"
      magick "$src_icon" -resize "''${size}x''${size}" \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/t3code-desktop.png"
    done
    # Keep the original 1024 as-is
    install -Dm644 "$src_icon" \
      "$out/share/icons/hicolor/1024x1024/apps/t3code-desktop.png"
    # pixmaps fallback for DEs that don't walk hicolor
    install -Dm644 /dev/null "$out/share/pixmaps/t3code-desktop.png"
    magick "$src_icon" -resize 256x256 "$out/share/pixmaps/t3code-desktop.png"

    install -Dm644 ${desktopItem}/share/applications/t3code-desktop.desktop \
      "$out/share/applications/t3code-desktop.desktop"

    # Wrap the Electrobun launcher so the shell app finds both t3 and the
    # pdeath-exec shim without depending on PATH.
    makeBinaryWrapper "$out/share/t3code-desktop/app/bin/launcher" "$out/bin/t3code-desktop" \
      --set-default T3CODE_DESKTOP_BIN "${t3code}/bin/t3" \
      --set-default T3CODE_DESKTOP_PDEATH_EXEC "${pdeathExec}/bin/pdeath-exec"

    runHook postInstall
  '';

  meta = {
    description = "Electrobun native-window wrapper around t3code";
    homepage = "https://github.com/pingdotgg/t3code";
    changelog = "https://github.com/pingdotgg/t3code/commits/main";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.mit;
    mainProgram = "t3code-desktop";
  };
}
