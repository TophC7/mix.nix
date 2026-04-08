# t3code-desktop - Electrobun native-window wrapper around the t3code CLI
#
# Runs the `t3` server as a child process of a small Bun shell app, then opens
# an Electrobun window (system webview, not CEF) pointed at the local server.
# Closing the window terminates the child t3 process via Bun's process hooks.
#
# Layout:
#   default.nix            - this derivation
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

  # Sibling package. Importing directly (rather than going through a
  # per-package callPackage scope) keeps the auto-discovery pattern simple.
  t3code = import ../t3code { inherit lib pkgs; };

  electrobunVersion = "1.16.0";

  # Prebuilt Electrobun binaries from upstream GH releases. Fetching these
  # separately (rather than letting electrobun's own wrapper download them at
  # runtime) keeps the main build hermetic.
  electrobunCli = fetchurl {
    url = "https://github.com/blackboardsh/electrobun/releases/download/v${electrobunVersion}/electrobun-cli-linux-x64.tar.gz";
    hash = "sha256-lBKJBx4oSEl/mo67cKrlbuwd07dQYJrgxjQxZzZe5m0=";
  };
  electrobunCore = fetchurl {
    url = "https://github.com/blackboardsh/electrobun/releases/download/v${electrobunVersion}/electrobun-core-linux-x64.tar.gz";
    hash = "sha256-p0aLbSaT4OV2jajdU+ecSC1D0rU5dykqbU1RwBIpYIQ=";
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

    nativeBuildInputs = [ pkgs.bun ];

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
    outputHash = "sha256-SPXONtPW+uoLh3zBkfzPjmsCfMP+Ika+VOyfwIvMYZ4=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "t3code-desktop";
  version = "0.0.1";

  src = shellSrc;

  __structuredAttrs = true;

  nativeBuildInputs = [
    pkgs.bun
    pkgs.nodejs_24
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
    # cjs wrapper expects it (so it skips its GitHub download path).
    mkdir -p node_modules/electrobun/bin
    tar -xzf ${electrobunCli} -C node_modules/electrobun/bin
    chmod +x node_modules/electrobun/bin/electrobun

    # Place the platform runtime (bun, launcher, libNativeWrapper.so, api/,
    # etc.) under dist-linux-x64/ where the CLI expects it.
    mkdir -p node_modules/electrobun/dist-linux-x64
    tar -xzf ${electrobunCore} -C node_modules/electrobun/dist-linux-x64
    chmod -R u+w node_modules/electrobun/dist-linux-x64
    # The launcher and helpers need the exec bit
    chmod +x node_modules/electrobun/dist-linux-x64/{bun,launcher,bsdiff,bspatch,extractor,process_helper,zig-asar,zig-zstd} 2>/dev/null || true

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

    # Invoke the CLI binary directly -- skipping the cjs wrapper -- to avoid
    # any filesystem prodding it does for its "cache" path.
    ./node_modules/electrobun/bin/electrobun build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/t3code-desktop"
    cp -a build/dev-linux-x64/t3code-desktop-dev "$out/share/t3code-desktop/app"

    # Re-patch the ELF bits we just copied in. The postPatch autoPatchelf run
    # set RPATHs that reference /build/shell/node_modules/..., which (a)
    # won't exist at runtime and (b) trips the fixup-phase check for
    # forbidden /build/ references. Running it again against $out rewrites
    # RPATHs to point at the store paths of the buildInputs we already
    # declared.
    autoPatchelf "$out/share/t3code-desktop/app/bin"

    # Launcher: set T3CODE_DESKTOP_BIN to our already-packaged t3 so the
    # shell app's spawn() finds it without PATH setup, then exec the
    # Electrobun launcher binary which runs our bundled Bun entry.
    makeBinaryWrapper "$out/share/t3code-desktop/app/bin/launcher" "$out/bin/t3code-desktop" \
      --set-default T3CODE_DESKTOP_BIN "${t3code}/bin/t3"

    runHook postInstall
  '';

  meta = {
    description = "Electrobun native-window wrapper around t3code";
    homepage = "https://github.com/pingdotgg/t3code";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.mit;
    mainProgram = "t3code-desktop";
  };
})
