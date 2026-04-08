# t3code - a minimal web GUI for coding agents (Codex, Claude Code)
# Upstream: https://github.com/pingdotgg/t3code
#
# Packages the `t3` CLI (apps/server) from source, tracking git main.
# The CLI boots a local HTTP/WS server and opens the web UI (apps/web) in
# your default browser -- no Electron involved.
#
# Why FoD for deps (not bun2nix):
#   bun2nix does not yet support Bun's `catalog:` protocol
#   (nix-community/bun2nix#66), which t3code relies on extensively across
#   its workspace. Instead we use a fixed-output derivation that runs
#   `bun install` with network access and captures node_modules; the hash
#   in version.json pins the exact tree so rebuilds are reproducible.
#   update.fish refreshes depsHash whenever rev changes.
#
# Files:
#   default.nix   - this derivation
#   version.json  - rev, srcHash, depsHash (updated by update.fish)
#   update.fish   - fetches latest main, rehashes src and deps
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

  # Fixed-output derivation: installs all Bun workspace dependencies
  # with network access (allowed only for FoDs) and captures the resulting
  # node_modules trees. Because outputHash is pinned, any drift in the
  # lockfile or registry content produces a hash mismatch and fails loudly.
  bunDeps = stdenvNoCC.mkDerivation {
    pname = "t3code-bun-deps";
    version = versionInfo.version;
    inherit src;

    nativeBuildInputs = [
      pkgs.bun
      pkgs.cacert
      pkgs.nodejs_24 # for native module builds (node-pty via node-gyp)
      pkgs.python3 # node-gyp requires python
      pkgs.pkg-config
    ];

    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    # `bun install` writes into a few places. We funnel everything into a
    # tempdir HOME so the build is self-contained, then harvest node_modules
    # directories from the workspace tree and drop them into $out with the
    # same relative paths so the main derivation can copy them back in.
    installPhase = ''
      runHook preInstall

      export HOME=$(mktemp -d)
      export BUN_INSTALL="$HOME/.bun"

      # --ignore-scripts is required because some workspace `prepare` hooks
      # (e.g. @t3tools/contracts -> effect-language-service patch) execute
      # binaries whose shebangs reference /usr/bin/env, which doesn't exist
      # in the Nix sandbox. The main derivation patches shebangs and
      # rebuilds the one native module we actually need (node-pty) after
      # this cache is copied back in.
      #
      # --linker=hoisted produces a classic flat node_modules layout so
      # Node's resolution walks cleanly from apps/server/dist/bin.mjs
      # upward and finds everything in a single node_modules tree.
      bun install --frozen-lockfile --ignore-scripts --linker=hoisted

      mkdir -p $out
      # Capture every node_modules directory bun created. Excludes nested
      # node_modules inside already-copied trees so we don't double-copy
      # the same content when bun uses hoisted install layouts.
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
    outputHash = versionInfo.depsHash;
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "t3code";
  version = versionInfo.version;

  inherit src;

  nativeBuildInputs = [
    pkgs.bun
    pkgs.nodejs_24
    pkgs.python3 # for node-gyp rebuild of node-pty
    pkgs.makeBinaryWrapper
  ];

  # Inject the pre-installed node_modules trees into the source tree, patch
  # shebangs (they still reference /usr/bin/env from the registry tarballs),
  # then rebuild node-pty since its postinstall was skipped in the FoD.
  postPatch = ''
    cp -a ${bunDeps}/. .
    chmod -R u+w .

    patchShebangs node_modules

    # Point node-gyp at the in-tree node headers and give it a writable
    # HOME so it doesn't try to download headers from nodejs.org or write
    # to /homeless-shelter.
    export HOME=$(mktemp -d)
    export npm_config_cache=$(mktemp -d)
    export npm_config_nodedir=${pkgs.nodejs_24}
    export npm_config_build_from_source=true

    # Rebuild only the native module we actually need at runtime. Using
    # npm here because it has `rebuild` baked in and the packaged node-pty
    # ships node-gyp as a transitive dep in node_modules.
    (cd node_modules/node-pty && ${pkgs.nodejs_24}/bin/npm rebuild)
  '';

  buildPhase = ''
    runHook preBuild

    export HOME=$(mktemp -d)
    export TURBO_TELEMETRY_DISABLED=1
    export DO_NOT_TRACK=1

    # Build the web UI and the server. The server's build script copies
    # apps/web/dist/ into apps/server/dist/client/, so web must run first.
    # turbo resolves the ordering when both filters are given.
    bun run turbo run build --filter=@t3tools/web --filter=t3 --no-daemon

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/t3code"
    cp -r apps/server/dist "$out/share/t3code/dist"

    # Runtime deps: tsdown leaves npm packages as external imports, so the
    # launcher needs node_modules at runtime. Ship the root node_modules
    # tree (hoisted external deps + native modules like node-pty).
    cp -a node_modules "$out/share/t3code/node_modules"

    # tsdown's `noExternal: "@t3tools/"` inlines every workspace package
    # into the bundle, so the `@t3tools/*` and `t3` symlinks in node_modules
    # (which point back at the source tree we don't ship) are dead weight
    # and would trip the noBrokenSymlinks check. Drop them.
    rm -rf "$out/share/t3code/node_modules/@t3tools"
    rm -f "$out/share/t3code/node_modules/t3"

    # Launcher: Node runs the bundled CLI entry. bin.mjs is the ESM output
    # from tsdown for the `bin.ts` entry in apps/server/tsdown.config.ts.
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
})
