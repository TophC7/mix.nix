# t3code-desktop - Electrobun native-window wrapper around the t3code CLI
#
# Runs the `t3` server as a child process of a small Bun shell app, then
# opens an Electrobun window (system webview, not CEF) pointed at the local
# server. Child-process cleanup happens at the kernel level via a tiny
# prctl(PR_SET_PDEATHSIG) wrapper around t3 -- Electrobun's GTK FFI loop
# blocks JS signal delivery, so bun-side `process.on("SIGTERM", ...)`
# handlers can't be relied on for tearing down the child.
#
# Layout:
#   default.nix            - this derivation
#   version.json           - electrobun version + all mutable hashes
#   update.fish            - refreshes version.json
#   shell/                 - source of our Electrobun shell app
#     package.json         - declares `electrobun` as a dep (+ bun types)
#     bun.lock             - pinned by bun; used for the deterministic FoD
#     electrobun.config.ts - bundleCEF: false on all platforms
#     tsconfig.json
#     src/bun/index.ts     - spawns t3, waits for port, opens BrowserWindow
{
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs) stdenv stdenvNoCC fetchurl;

  versionInfo = lib.importJSON ./version.json;

  # Sibling package. Importing directly (rather than going through a
  # per-package callPackage scope) keeps the auto-discovery pattern simple.
  t3code = import ../t3code { inherit lib pkgs; };

  # Prebuilt Electrobun binaries from upstream GH releases. Fetching these
  # separately (rather than letting electrobun's own wrapper download them
  # at runtime) keeps the main build hermetic.
  electrobunCli = fetchurl {
    url = "https://github.com/blackboardsh/electrobun/releases/download/v${versionInfo.electrobun.version}/electrobun-cli-linux-x64.tar.gz";
    hash = versionInfo.electrobun.cliHash;
  };
  electrobunCore = fetchurl {
    url = "https://github.com/blackboardsh/electrobun/releases/download/v${versionInfo.electrobun.version}/electrobun-core-linux-x64.tar.gz";
    hash = versionInfo.electrobun.coreHash;
  };

  # Upstream icon, pinned by commit so the hash is stable. update.fish
  # keeps this in sync with t3code's rev so the icon follows the package.
  icon = fetchurl {
    url = "https://raw.githubusercontent.com/pingdotgg/t3code/${versionInfo.icon.rev}/assets/prod/black-universal-1024.png";
    hash = versionInfo.icon.hash;
  };

  # Tiny C shim: call prctl(PR_SET_PDEATHSIG, SIGTERM) then execvp the
  # target. Used to wrap the t3 child process so the kernel tears it down
  # the instant its direct parent (our bun shell) dies -- working around
  # the fact that Electrobun's GTK FFI loop blocks JS signal delivery, so
  # bun-side `process.on("SIGTERM", ...)` handlers never run when the
  # Electrobun launcher forwards signals.
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

  # XDG desktop entry. StartupWMClass must match what Electrobun sets as
  # the window class so desktop environments group taskbar entries and pin
  # launches correctly. Stable builds use the bare app.name from the
  # electrobun config (no `-dev` or `-canary` suffix), so this matches.
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

  # Runtime libraries the Electrobun launcher + libNativeWrapper.so link
  # against on Linux. system-webview (no CEF) means we need webkit2gtk-4.1
  # plus its GTK stack. autoPatchelfHook rewrites DT_NEEDED entries to point
  # at these store paths.
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

  # Fixed-output derivation: installs the shell project's deps (electrobun +
  # its transitive deps three, @babylonjs/core, proxy-agent, etc.) via bun.
  # Same pattern as packages/t3code.
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
  ];

  buildInputs = runtimeLibs;

  # libcef.so is only needed by process_helper/libNativeWrapper_cef.so when
  # the app uses the CEF renderer. Our electrobun.config.ts sets
  # bundleCEF: false on Linux so we never dlopen CEF.
  autoPatchelfIgnoreMissingDeps = [ "libcef.so" ];

  # Inject deps + pre-fetched Electrobun binaries into the source tree, then
  # patch ELF + shebangs so the CLI and launcher actually run on NixOS.
  postPatch = ''
    cp -a ${bunDeps}/node_modules ./node_modules
    chmod -R u+w ./node_modules

    # Place the compiled CLI under node_modules/electrobun/bin/ where the
    # cjs wrapper expects it (so it skips its GitHub download path). tar
    # preserves the executable bit, no chmod needed.
    mkdir -p node_modules/electrobun/bin
    tar -xzf ${electrobunCli} -C node_modules/electrobun/bin

    # Place the platform runtime (bun, launcher, libNativeWrapper.so, api/,
    # etc.) under dist-linux-x64/ where the CLI expects it.
    mkdir -p node_modules/electrobun/dist-linux-x64
    tar -xzf ${electrobunCore} -C node_modules/electrobun/dist-linux-x64

    patchShebangs node_modules

    # autoPatchelfHook normally runs at fixup time, but we need the ELF
    # binaries runnable during the build phase because we invoke the
    # Electrobun CLI then. Run the helper manually against the trees we
    # just dropped into place.
    autoPatchelf \
      node_modules/electrobun/bin \
      node_modules/electrobun/dist-linux-x64
  '';

  buildPhase = ''
    runHook preBuild

    export HOME=$(mktemp -d)

    # --env=stable produces:
    #   build/stable-linux-x64/t3code-desktop/    (self-extracting installer variant - unusable in Nix store)
    #   artifacts/stable-linux-x64-t3code-desktop.tar.zst  (normal runnable app - what we ship)
    #
    # The --env flag requires --env=VALUE form; --env VALUE is silently
    # ignored and falls back to "dev".
    ./node_modules/electrobun/bin/electrobun build --env=stable

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    # The stable .tar.zst payload contains a normal statically-linked Zig
    # launcher + Resources/main.js + bun/libs -- same shape as a dev build
    # but without the "-dev" channel suffix. The top-level directory inside
    # the archive is `t3code-desktop/`; --strip-components=1 drops that and
    # lands its contents directly in $out/share/t3code-desktop/app/.
    mkdir -p "$out/share/t3code-desktop/app"
    tar --zstd -xf artifacts/stable-linux-x64-t3code-desktop.tar.zst \
      -C "$out/share/t3code-desktop/app" --strip-components=1

    # Re-patch the ELF bits we just extracted. The bun binary and
    # libNativeWrapper.so inside the tarball still have Ubuntu-style
    # DT_NEEDED entries that need rewriting to point at NixOS store paths.
    autoPatchelf "$out/share/t3code-desktop/app/bin"

    # XDG icon: installing the 1024x1024 PNG under hicolor/1024x1024/apps/
    # lets desktop environments scale it down for menus, docks, and task
    # switchers. The basename must match the Icon= field in the .desktop
    # entry ("t3code-desktop").
    install -Dm644 ${icon} "$out/share/icons/hicolor/1024x1024/apps/t3code-desktop.png"

    # XDG desktop entry for app launchers / menus.
    install -Dm644 ${desktopItem}/share/applications/t3code-desktop.desktop \
      "$out/share/applications/t3code-desktop.desktop"

    # Launcher: set T3CODE_DESKTOP_BIN to our already-packaged t3 so the
    # shell app's spawn() finds it without PATH setup, then exec the
    # Electrobun launcher binary which runs our bundled Bun entry.
    # T3CODE_DESKTOP_PDEATH_EXEC points at our prctl wrapper so the shell
    # app can opt into kernel-driven child cleanup.
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
