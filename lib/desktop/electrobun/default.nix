# Electrobun desktop app builder
#
# Creates native desktop applications using Electrobun (system webview, no
# CEF). Produces a self-contained app bundle with a binary wrapper, icons at
# all standard hicolor sizes, and a .desktop entry.
#
# Two modes:
#   url     — connect to an external URL (self-hosted services like Catnip)
#   command — spawn a child process and connect to its HTTP server (like t3code)
#
# Usage:
#   # URL mode (self-hosted service)
#   lib.desktop.mkElectrobunApp pkgs {
#     pname = "catnip-desktop";
#     desktopName = "Catnip";
#     identifier = "foo.ryot.catnip-desktop";
#     icon = ./icon.png;
#     url.default = "http://localhost:6369";
#   }
#
#   # Command mode (spawn + wrap)
#   lib.desktop.mkElectrobunApp pkgs {
#     pname = "t3code-desktop";
#     desktopName = "T3 Code";
#     identifier = "foo.ryot.t3code-desktop";
#     icon = "${t3code.src}/assets/prod/black-universal-1024.png";
#     command = {
#       package = t3code;
#       binName = "t3";
#       args = [ "--no-browser" "--port" "{port}" "--host" "{host}" ];
#       defaultPort = 18822;
#     };
#   }
#
{ lib }:
let
  defaultVersionInfo = lib.importJSON ./version.json;

  # The shell template's package.json name ("t3code-desktop-shell") is an
  # artifact of the original project. Changing it would invalidate the
  # bun.lock and bunDepsHash. It does not affect the output.
  shellTemplate = ./shell;

  # Length of the hardcoded WM_CLASS string in Electrobun's libNativeWrapper.so.
  # All byte-offset constants (padding, dd count, assert limit) derive from this.
  wmclassOriginal = "ElectrobunKitchenSink-dev";
  wmclassLen = builtins.stringLength wmclassOriginal;
in
{
  mkElectrobunApp =
    pkgs:
    {
      pname,
      version ? "0.0.1",

      # Desktop entry fields
      desktopName,
      genericName ? null,
      comment ? null,
      categories ? [ "Utility" ],
      icon, # path to source PNG (ideally ≥512px)
      startupWMClass ? pname,

      # Electrobun app identity (reverse-domain)
      identifier,

      # Exactly one of url or command must be set.
      #   url     = { default = "http://..."; envVar? = "FOO_URL"; }
      #   command = { package; binName; args? = []; defaultPort? = 18822; defaultHost? = "127.0.0.1"; }
      url ? null,
      command ? null,

      # Window geometry
      window ? { },
      title ? desktopName,

      # How long to wait for the HTTP server before giving up (ms)
      readinessTimeoutMs ? 15000,

      # Env var prefix (default: UPPER(pname) with - → _)
      envPrefix ? null,

      # Escape hatches
      extraWrapperArgs ? [ ],
      extraRuntimeLibs ? [ ],
      meta ? { },

      # Override Electrobun version + hashes (defaults to ./version.json)
      electrobunVersionInfo ? defaultVersionInfo,
    }:
    # ── Input validation ─────────────────────────────────────────────────
    assert lib.assertMsg ((url != null) != (command != null))
      "mkElectrobunApp: exactly one of 'url' or 'command' must be set";
    assert lib.assertMsg (url == null || url ? default)
      "mkElectrobunApp: url.default is required (the URL to connect to)";
    assert lib.assertMsg (command == null || command ? package)
      "mkElectrobunApp: command.package is required (the derivation containing the binary)";
    assert lib.assertMsg (command == null || command ? binName)
      "mkElectrobunApp: command.binName is required (the binary name within the package)";
    assert lib.assertMsg (builtins.stringLength startupWMClass <= (wmclassLen - 1))
      "mkElectrobunApp: startupWMClass '${startupWMClass}' exceeds ${toString (wmclassLen - 1)} bytes (max for Electrobun WM_CLASS patch)";
    assert lib.assertMsg (builtins.match "[a-zA-Z0-9._-]+" identifier != null)
      "mkElectrobunApp: identifier '${identifier}' must be alphanumeric with dots/hyphens/underscores";
    let
      inherit (pkgs) stdenv stdenvNoCC fetchurl;

      versionInfo = electrobunVersionInfo;
      mode = if url != null then "url" else "command";

      prefix =
        if envPrefix != null then
          envPrefix
        else
          lib.strings.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] pname);

      windowWidth = window.width or 1200;
      windowHeight = window.height or 800;

      # ── Build-time config (injected into the TS bundle as JSON) ────────
      # Structured as a discriminated union so the TypeScript side can
      # narrow on `mode` without non-null assertions.

      sharedConfig = {
        inherit mode title readinessTimeoutMs;
        window = {
          width = windowWidth;
          height = windowHeight;
        };
        envPrefix = prefix;
      };

      runtimeConfig = builtins.toJSON (
        if mode == "url" then
          sharedConfig
          // {
            url = {
              default = url.default;
              envVar = url.envVar or "${prefix}_URL";
            };
          }
        else
          sharedConfig
          // {
            command = {
              binEnvVar = "${prefix}_BIN";
              args = command.args or [ ];
              portDefault = command.defaultPort or 18822;
              portEnvVar = "${prefix}_PORT";
              hostDefault = command.defaultHost or "127.0.0.1";
              hostEnvVar = "${prefix}_HOST";
              cwdEnvVar = "${prefix}_CWD";
              pdeathExecEnvVar = "${prefix}_PDEATH_EXEC";
            };
          }
      );

      configJsonFile = pkgs.writeText "${pname}-config.json" runtimeConfig;

      electrobunConfigTs = pkgs.writeText "${pname}-electrobun-config.ts" ''
        import type { ElectrobunConfig } from "electrobun";
        export default {
          app: {
            name: "${pname}",
            identifier: "${identifier}",
            version: "${version}",
          },
          build: {
            bun: { entrypoint: "src/bun/index.ts" },
            views: {},
            linux: { bundleCEF: false },
            mac: { bundleCEF: false },
            win: { bundleCEF: false },
          },
        } satisfies ElectrobunConfig;
      '';

      # ── Prebuilt Electrobun binaries ───────────────────────────────────

      electrobunCli = fetchurl {
        url = "https://github.com/blackboardsh/electrobun/releases/download/v${versionInfo.electrobun.version}/electrobun-cli-linux-x64.tar.gz";
        hash = versionInfo.electrobun.cliHash;
      };

      electrobunCore = fetchurl {
        url = "https://github.com/blackboardsh/electrobun/releases/download/v${versionInfo.electrobun.version}/electrobun-core-linux-x64.tar.gz";
        hash = versionInfo.electrobun.coreHash;
      };

      # prctl(PR_SET_PDEATHSIG, SIGTERM) then execvp — kernel-level child
      # cleanup. Electrobun's GTK FFI loop blocks JS signal delivery, so
      # process.on("SIGTERM") can't be relied on. This shim guarantees the
      # child dies when the parent does.
      # Only compiled in command mode (url mode has no child process).
      pdeathExec = lib.optionalString (mode == "command") (
        pkgs.writeCBin "pdeath-exec" ''
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
        ''
      );

      # ── Desktop entry ──────────────────────────────────────────────────

      desktopItem = pkgs.makeDesktopItem (
        {
          name = pname;
          inherit desktopName startupWMClass categories;
          exec = pname;
          icon = pname;
          startupNotify = true;
          terminal = false;
        }
        // lib.optionalAttrs (genericName != null) { inherit genericName; }
        // lib.optionalAttrs (comment != null) { inherit comment; }
      );

      # ── Runtime library closure ────────────────────────────────────────

      runtimeLibs = with pkgs; [
        webkitgtk_4_1
        gtk3
        glib
        glib-networking # GnuTLS backend for GIO — without this, webkit2gtk cannot load HTTPS URLs
        libsoup_3
        cairo
        pango
        gdk-pixbuf
        atk
        harfbuzz
        libxkbcommon
        libayatana-appindicator
        stdenv.cc.cc.lib
      ] ++ extraRuntimeLibs;

      # ── FoD for bun deps ───────────────────────────────────────────────
      # All apps share the same shell template (same electrobun version),
      # so this derivation's output hash is identical across consumers.

      bunDeps = stdenvNoCC.mkDerivation {
        pname = "${pname}-bun-deps";
        inherit version;
        src = shellTemplate;

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

      # ── Binary wrapper args ────────────────────────────────────────────

      wrapperArgs =
        lib.optionals (mode == "command") [
          "--set-default"
          "${prefix}_BIN"
          "${command.package}/bin/${command.binName}"
          "--set-default"
          "${prefix}_PDEATH_EXEC"
          "${pdeathExec}/bin/pdeath-exec"
        ]
        ++ extraWrapperArgs;
    in
    stdenv.mkDerivation {
      inherit pname version;

      src = shellTemplate;

      nativeBuildInputs = [
        pkgs.bun
        pkgs.nodejs_24
        pkgs.zstd
        pkgs.makeBinaryWrapper
        pkgs.autoPatchelfHook
        pkgs.imagemagick
      ];

      buildInputs = runtimeLibs;

      # libcef.so is only dlopen'd with the CEF renderer; we set
      # bundleCEF: false so it's never loaded.
      autoPatchelfIgnoreMissingDeps = [ "libcef.so" ];

      postPatch = ''
        cp -a ${bunDeps}/node_modules ./node_modules
        chmod -R u+w ./node_modules

        mkdir -p node_modules/electrobun/bin node_modules/electrobun/dist-linux-x64
        tar -xzf ${electrobunCli} -C node_modules/electrobun/bin
        tar -xzf ${electrobunCore} -C node_modules/electrobun/dist-linux-x64

        patchShebangs node_modules
        autoPatchelf \
          node_modules/electrobun/bin \
          node_modules/electrobun/dist-linux-x64

        # Overlay generated config onto the shared shell template
        cp ${electrobunConfigTs} electrobun.config.ts
        cp ${configJsonFile} src/bun/config.json
      '';

      buildPhase = ''
        runHook preBuild
        export HOME=$(mktemp -d)
        # --env=stable (not --env stable — the CLI silently falls back to "dev")
        ./node_modules/electrobun/bin/electrobun build --env=stable
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p "$out/share/${pname}/app"
        tar --zstd -xf artifacts/stable-linux-x64-${pname}.tar.zst \
          -C "$out/share/${pname}/app" --strip-components=1

        autoPatchelf "$out/share/${pname}/app/bin"

        # Patch hardcoded WM_CLASS in libNativeWrapper.so — Electrobun v1.16.0
        # bakes "${wmclassOriginal}" into .rodata which is passed to
        # gtk_window_set_wmclass() and read by Wayland compositors as app_id.
        # Overwrite in place, padded with NULs to preserve byte offsets.
        wmclass_len=${toString wmclassLen}
        libWrapper="$out/share/${pname}/app/bin/libNativeWrapper.so"
        chmod u+w "$libWrapper"
        offset=$(grep -abo '${wmclassOriginal}' "$libWrapper" | head -1 | cut -d: -f1)
        if [ -z "$offset" ]; then
          echo "error: libNativeWrapper.so no longer contains the hardcoded WM_CLASS string;" >&2
          echo "       upstream Electrobun may have fixed the bug -- drop this patch." >&2
          exit 1
        fi
        { printf '%s' '${startupWMClass}'; printf '\0%.0s' $(seq 1 "$wmclass_len"); } \
          | head -c "$wmclass_len" \
          | dd of="$libWrapper" bs=1 seek="$offset" count="$wmclass_len" conv=notrunc status=none

        # Icons at all standard hicolor sizes + pixmaps fallback
        src_icon="${icon}"
        for size in 16 24 32 48 64 128 256 512; do
          mkdir -p "$out/share/icons/hicolor/''${size}x''${size}/apps"
          magick "$src_icon" -resize "''${size}x''${size}" \
            "$out/share/icons/hicolor/''${size}x''${size}/apps/${pname}.png"
        done
        install -Dm644 "$src_icon" \
          "$out/share/icons/hicolor/1024x1024/apps/${pname}.png"
        mkdir -p "$out/share/pixmaps"
        magick "$src_icon" -resize 256x256 "$out/share/pixmaps/${pname}.png"

        install -Dm644 ${desktopItem}/share/applications/${pname}.desktop \
          "$out/share/applications/${pname}.desktop"

        makeBinaryWrapper "$out/share/${pname}/app/bin/launcher" "$out/bin/${pname}" \
          ${lib.concatMapStringsSep " " lib.escapeShellArg wrapperArgs}

        runHook postInstall
      '';

      passthru = {
        electrobunVersion = versionInfo.electrobun.version;
        inherit mode;
      } // lib.optionalAttrs (mode == "command") {
        commandPackage = command.package;
      };

      meta = {
        platforms = [ "x86_64-linux" ];
        mainProgram = pname;
      } // meta;
    };
}
