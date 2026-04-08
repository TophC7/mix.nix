# Wails desktop app builder
#
# Creates native desktop applications using Wails v2 (system webview via
# webkit2gtk, native Wayland support). Produces a self-contained binary
# with icons at all standard hicolor sizes and a .desktop entry.
#
# Two modes:
#   url     — connect to an external URL (self-hosted services)
#   command — spawn a child process and connect to its HTTP server
#
# Usage:
#   # URL mode (self-hosted service)
#   lib.desktop.mkWailsApp pkgs {
#     pname = "catnip-desktop";
#     desktopName = "Catnip";
#     programName = "catnip-desktop";
#     icon = ./icon.png;
#     url.default = "http://localhost:6369";
#   }
#
#   # Command mode (spawn + wrap)
#   lib.desktop.mkWailsApp pkgs {
#     pname = "t3code-desktop";
#     desktopName = "T3 Code";
#     programName = "t3code-desktop";
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
  versionInfo = lib.importJSON ./version.json;
  shellTemplate = ./shell;
in
{
  mkWailsApp =
    pkgs:
    {
      pname,
      version ? "0.0.1",

      # Desktop entry fields
      desktopName,
      genericName ? null,
      comment ? null,
      categories ? [ "Utility" ],
      icon, # path to source PNG (ideally >=512px)

      # Wayland app_id / X11 WM_CLASS — set via g_set_prgname() in Wails
      programName ? pname,

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

      # Env var prefix (default: UPPER(pname) with - -> _)
      envPrefix ? null,

      # Override the monospace font in the webview via fontconfig.
      #   monoFont = { package = monocraft-nerd-fonts; name = "Monocraft Nerd Font"; }
      monoFont ? null,

      # Escape hatches
      extraWrapperArgs ? [ ],
      meta ? { },
    }:
    # ── Input validation ─────────────────────────────────────────────────
    assert lib.assertMsg (
      (url != null) != (command != null)
    ) "mkWailsApp: exactly one of 'url' or 'command' must be set";
    assert lib.assertMsg (
      url == null || url ? default
    ) "mkWailsApp: url.default is required (the URL to connect to)";
    assert lib.assertMsg (
      command == null || command ? package
    ) "mkWailsApp: command.package is required (the derivation containing the binary)";
    assert lib.assertMsg (
      command == null || command ? binName
    ) "mkWailsApp: command.binName is required (the binary name within the package)";
    let
      mode = if url != null then "url" else "command";

      prefix =
        if envPrefix != null then
          envPrefix
        else
          lib.strings.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] pname);

      windowWidth = window.width or 1200;
      windowHeight = window.height or 800;

      # ── Build-time config (embedded into the Go binary as JSON) ────────
      sharedConfig = {
        inherit mode title programName readinessTimeoutMs;
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
            };
          }
      );

      configJsonFile = pkgs.writeText "${pname}-config.json" runtimeConfig;

      # ── Desktop entry ──────────────────────────────────────────────────
      desktopItem = pkgs.makeDesktopItem (
        {
          name = pname;
          inherit desktopName categories;
          exec = pname;
          icon = pname;
          startupNotify = true;
          startupWMClass = programName;
          terminal = false;
        }
        // lib.optionalAttrs (genericName != null) { inherit genericName; }
        // lib.optionalAttrs (comment != null) { inherit comment; }
      );

      # ── Fontconfig override (monospace font) ────────────────────────────
      fontconfigFile = lib.optionalString (monoFont != null) (
        pkgs.writeText "${pname}-fonts.conf" ''
          <?xml version="1.0"?>
          <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
          <fontconfig>
            <include ignore_missing="yes">/etc/fonts/fonts.conf</include>
            <dir>${monoFont.package}/share/fonts</dir>
            <match target="pattern">
              <test name="family" qual="any"><string>monospace</string></test>
              <edit name="family" mode="prepend" binding="strong">
                <string>${monoFont.name}</string>
              </edit>
            </match>
          </fontconfig>
        ''
      );

      # ── Binary wrapper args ────────────────────────────────────────────
      wrapperArgs =
        lib.optionals (mode == "command") [
          "--set-default"
          "${prefix}_BIN"
          "${command.package}/bin/${command.binName}"
        ]
        ++ extraWrapperArgs;
    in
    pkgs.buildGoModule {
      inherit pname version;

      src = shellTemplate;
      vendorHash = versionInfo.vendorHash;

      tags = [ "webkit2_41" "production" ];

      nativeBuildInputs = with pkgs; [
        pkg-config
        makeWrapper
        imagemagick
        glib # for GSettings schemas
      ];

      buildInputs = with pkgs; [
        webkitgtk_4_1
        gtk3
        glib-networking # GnuTLS backend for GIO — HTTPS in webview
      ];

      preBuild = ''
        cp ${configJsonFile} config.json
      '';

      postInstall = ''
        # Rename the binary from the Go module name to our pname
        if [ ! -f "$out/bin/mix-nix-wails-shell" ]; then
          echo "error: expected $out/bin/mix-nix-wails-shell not found — Go module name may have changed" >&2
          exit 1
        fi
        mv "$out/bin/mix-nix-wails-shell" "$out/bin/.${pname}-unwrapped"

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

        # Wrap the binary — capture caller's $PWD for command mode
        makeWrapper "$out/bin/.${pname}-unwrapped" "$out/bin/${pname}" \
          ${
            lib.optionalString (mode == "command")
            ''--run 'export ${prefix}_CWD="''${${prefix}_CWD:-$(pwd)}"' ''
          } \
          --prefix GIO_EXTRA_MODULES : "${pkgs.glib-networking}/lib/gio/modules" \
          ${lib.optionalString (monoFont != null) ''--set FONTCONFIG_FILE "${fontconfigFile}"''} \
          ${lib.concatMapStringsSep " " lib.escapeShellArg wrapperArgs}
      '';

      passthru = {
        wailsVersion = versionInfo.wails;
        inherit mode programName;
      } // lib.optionalAttrs (mode == "command") {
        commandPackage = command.package;
      };

      meta = {
        platforms = [ "x86_64-linux" ];
        mainProgram = pname;
      } // meta;
    };
}
