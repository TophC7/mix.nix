# t3code - minimal web GUI for coding agents (Codex, Claude Code).
# Upstream: https://github.com/pingdotgg/t3code
#
# Packages the `t3` CLI (apps/server) from source, tracking git main.
#
# Deps are fetched via a fixed-output derivation (not bun2nix) because
# bun2nix does not yet support Bun's `catalog:` protocol, which t3code
# relies on extensively -- see nix-community/bun2nix#66.
{
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs) fetchFromGitHub stdenv stdenvNoCC;

  versionInfo = lib.importJSON ./version.json;

  src = fetchFromGitHub {
    owner = "pingdotgg";
    repo = "t3code";
    rev = versionInfo.rev;
    hash = versionInfo.hash;
  };

  # Two dep trees: `bunDeps` (full, for build-time tooling) and
  # `bunRuntimeDeps` (--production, shipped in $out). Each is its own FoD
  # since --production changes the resolved set.
  mkBunDeps =
    { nameSuffix, production }:
    stdenvNoCC.mkDerivation {
      pname = "t3code-bun-deps${nameSuffix}";
      version = versionInfo.version;
      inherit src;

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

        # --ignore-scripts: some workspace `prepare` hooks reference
        # /usr/bin/env which doesn't exist in the Nix sandbox; the main
        # derivation patches shebangs and rebuilds native modules after.
        # --linker=hoisted: flat node_modules so Node's resolution walks
        # cleanly from apps/server/dist/bin.mjs.
        bun install --frozen-lockfile --ignore-scripts --linker=hoisted ${
          lib.optionalString production "--production"
        }

        mkdir -p $out
        find . -name node_modules -type d -not -path '*/node_modules/*/node_modules*' \
          | while read -r nm; do
            relDir=$(dirname "$nm")
            mkdir -p "$out/$relDir"
            cp -a "$nm" "$out/$relDir/node_modules"
          done

        runHook postInstall
      '';

      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
    };

  bunDeps =
    (mkBunDeps {
      nameSuffix = "";
      production = false;
    }).overrideAttrs
      { outputHash = versionInfo.depsHash; };

  bunRuntimeDeps =
    (mkBunDeps {
      nameSuffix = "-runtime";
      production = true;
    }).overrideAttrs
      { outputHash = versionInfo.runtimeDepsHash; };
in
stdenv.mkDerivation {
  pname = "t3code";
  version = versionInfo.version;

  inherit src;

  nativeBuildInputs = [
    pkgs.bun
    pkgs.nodejs_24
    pkgs.python3 # for node-gyp rebuild of node-pty
    pkgs.makeBinaryWrapper
  ];

  postPatch = ''
    cp -a ${bunDeps}/. .
    chmod -R u+w .

    patchShebangs node_modules

    # Point node-gyp at in-tree node headers + give it a writable HOME so
    # it doesn't try to fetch from nodejs.org or write to /homeless-shelter.
    export HOME=$(mktemp -d)
    export npm_config_cache=$(mktemp -d)
    export npm_config_nodedir=${pkgs.nodejs_24}
    export npm_config_build_from_source=true

    # Rebuild node-pty (skipped by --ignore-scripts in the FoD).
    (cd node_modules/node-pty && ${pkgs.nodejs_24}/bin/npm rebuild)
  '';

  buildPhase = ''
    runHook preBuild

    export HOME=$(mktemp -d)
    export TURBO_TELEMETRY_DISABLED=1
    export DO_NOT_TRACK=1

    # turbo resolves the ordering: web must build first because the
    # server's build script copies apps/web/dist/ into the server bundle.
    bun run turbo run build --filter=@t3tools/web --filter=t3 --no-daemon

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/t3code"
    cp -r apps/server/dist "$out/share/t3code/dist"

    # Runtime tree (no dev tooling -- ~700MB smaller than bunDeps).
    cp -a ${bunRuntimeDeps}/node_modules "$out/share/t3code/node_modules"
    chmod -R u+w "$out/share/t3code/node_modules"

    # tsdown inlines @t3tools/* into the bundle via noExternal, so these
    # symlinks point at source we don't ship; they'd trip noBrokenSymlinks.
    rm -rf "$out/share/t3code/node_modules/@t3tools"
    rm -f "$out/share/t3code/node_modules/t3"

    # Carry over node-pty's .node bindings rebuilt in postPatch; its loader
    # resolves build/ relative to its own package dir. Fail loudly if
    # missing -- otherwise t3 crashes on first terminal spawn.
    if [ ! -f node_modules/node-pty/build/Release/pty.node ]; then
      echo "error: node-pty native binding missing; postPatch rebuild failed silently" >&2
      exit 1
    fi
    cp -a node_modules/node-pty/build \
      "$out/share/t3code/node_modules/node-pty/build"

    patchShebangs "$out/share/t3code/node_modules"

    makeBinaryWrapper "${pkgs.nodejs_24}/bin/node" "$out/bin/t3" \
      --add-flags "$out/share/t3code/dist/bin.mjs"

    runHook postInstall
  '';

  meta = {
    description = "Minimal web GUI for coding agents (Codex, Claude Code)";
    homepage = "https://github.com/pingdotgg/t3code";
    changelog = "https://github.com/pingdotgg/t3code/commits/main";
    platforms = lib.platforms.linux;
    license = lib.licenses.mit;
    mainProgram = "t3";
  };
}
