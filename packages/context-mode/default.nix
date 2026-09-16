{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  # Upstream's own bun2nix keeps the hook version-matched to its generated bun.nix.
  b2n = inputs.omp.inputs.bun2nix.packages.${system}.default;
  src = inputs.context-mode;
in
pkgs.stdenv.mkDerivation {
  pname = "context-mode";
  version = (lib.importJSON (src + "/package.json")).version;
  inherit src;

  strictDeps = true;
  nativeBuildInputs = [
    b2n.hook
    pkgs.bun
    pkgs.makeWrapper
    pkgs.nodejs
  ];

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
  ];

  postPatch = ''
    # Keep package.json consistent with bun.lock's optional native dependency.
    bun -e '
      const fs = require("fs");
      const packageJsonPath = "package.json";
      const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
      const betterSqliteVersion = packageJson.dependencies?.["better-sqlite3"];

      if (betterSqliteVersion) {
        packageJson.optionalDependencies = packageJson.optionalDependencies ?? {};
        packageJson.optionalDependencies["better-sqlite3"] = betterSqliteVersion;
        delete packageJson.dependencies["better-sqlite3"];
        fs.writeFileSync(packageJsonPath, JSON.stringify(packageJson, null, 2) + "\n");
      }
    '
  '';

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    bun run tsc
    chmod +x build/cli.js
    bun run bundle
    bun run assert-bundle
    bun run assert-asymmetric-drift
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    rm -rf node_modules
    bun install --production --offline --frozen-lockfile --ignore-scripts --linker=isolated

    mkdir -p $out
    bun -e '
      const fs = require("fs");
      const path = require("path");
      const packageJson = JSON.parse(fs.readFileSync("package.json", "utf8"));

      for (const entry of ["package.json", ...packageJson.files]) {
        fs.cpSync(entry, path.join(process.env.out, entry), { recursive: true });
      }
    '
    cp -R node_modules $out/

    mkdir -p $out/bin
    makeWrapper ${lib.getExe pkgs.nodejs} $out/bin/context-mode \
      --add-flags "$out/cli.bundle.mjs" \
      --prefix PATH : ${lib.makeBinPath [ pkgs.bun ]}
    runHook postInstall
  '';

  meta = {
    description = "Context window optimization for AI coding agents";
    homepage = "https://github.com/mksglu/context-mode";
    license = lib.licenses.elastic20;
    mainProgram = "context-mode";
    platforms = lib.platforms.unix;
  };
}
