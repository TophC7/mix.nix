{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  b2n = inputs.omp.inputs.bun2nix.packages.${system}.default;
  src = inputs.ompweb;
  # Reuse upstream's pinned fonts/patch, not its npm builder, source fileset, or deps.
  fontSetup = import (src + "/nix/package.nix") {
    inherit lib;
    inherit (pkgs) fetchurl writeText;
    buildNpmPackage = attrs: attrs { };
  };
in
pkgs.stdenv.mkDerivation {
  pname = "ompweb";
  version = "${(lib.importJSON (src + "/package.json")).version}-unstable-${builtins.substring 0 7 src.rev}";
  inherit src;
  inherit (fontSetup) patches;

  strictDeps = true;
  nativeBuildInputs = [
    b2n.hook
    pkgs.bun
    pkgs.makeWrapper
    pkgs.autoPatchelfHook
    # Stable patchelf corrupts libvips' DT_INIT when growing its RPATH.
    pkgs.patchelfUnstable
  ];
  buildInputs = [ pkgs.stdenv.cc.cc.lib ];

  bunDeps = b2n.fetchBunDeps {
    bunNix =
      args:
      let
        allDeps = pkgs.callPackage ./bun.nix args;
        isTarget =
          name:
          let
            isDarwin = builtins.match ".*(darwin).*" name != null;
            isWindows = builtins.match ".*(win32).*" name != null;
            isOtherOs = builtins.match ".*(android|freebsd|openbsd|netbsd|sunos|aix).*" name != null;
            isOtherArch =
              if pkgs.stdenv.hostPlatform.isx86_64 then
                builtins.match ".*(arm64|armv7|arm-linux|linux-arm|ia32|mips|ppc64|riscv64|s390x|loong64).*" name != null
              else if pkgs.stdenv.hostPlatform.isAarch64 then
                builtins.match ".*(x64|x86_64|ia32|mips|ppc64|riscv64|s390x|loong64|arm-linux|linux-arm).*" name != null
              else
                false;
          in
          !(isDarwin || isWindows || isOtherOs || isOtherArch);
      in
      lib.filterAttrs (name: _: isTarget name) allDeps;
  };

  dontRunLifecycleScripts = true;
  dontUseBunBuild = true;
  dontUseBunCheck = true;
  dontUseBunInstall = true;
  bunInstallFlags = [
    "--linker=isolated"
    "--offline"
    "--frozen-lockfile"
  ];

  postPatch = fontSetup.postPatch + ''
    cp ${./bun.lock} bun.lock
  '';

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    export NEXT_TELEMETRY_DISABLED=1
    bun --bun next build --webpack
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    rm -rf node_modules .next/cache
    bun install --production --offline --frozen-lockfile --ignore-scripts --linker=isolated
    # Bun also installs optional musl variants; NixOS uses only the glibc addons.
    rm -rf node_modules/.bun/*musl* node_modules/@*/*musl* \
      node_modules/.bun/node_modules/@*/*musl* \
      node_modules/.bun/*/node_modules/@*/*musl*
    mkdir -p $out/lib/ompweb $out/bin
    cp -R .next bin lib public scripts node_modules package.json next.config.ts $out/lib/ompweb/
    makeWrapper ${lib.getExe pkgs.bun} $out/bin/ompweb \
      --add-flags "$out/lib/ompweb/bin/omp-web.js" \
      --prefix PATH : ${lib.makeBinPath [ pkgs.bun ]} \
      --set NEXT_TELEMETRY_DISABLED 1
    runHook postInstall
  '';

  meta = {
    description = "Local web UI for the oh-my-pi (omp) coding agent, built and run with Bun";
    homepage = "https://github.com/kahme247/ompweb";
    license = lib.licenses.mit;
    mainProgram = "ompweb";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
