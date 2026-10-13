{
  lib,
  pkgs,
  ...
}:
let
  version = "6.4.0";
  pythonWithPwntools = pkgs.python3.withPackages (ps: [ ps.pwntools ]);
in
pkgs.buildNpmPackage {
  pname = "rea";
  inherit version;

  src = pkgs.fetchFromGitHub {
    owner = "morluto";
    repo = "rea";
    rev = "a56f7bb668ab23fec8d33f7af353ac7ed2fe1895";
    hash = "sha256-aAbOYpsT6QhlLAZDtVHZ1Acz6uIqrVEd4p49s/2FJgc=";
  };

  npmDepsHash = "sha256-XuiMtaM/MPDkhjiHCr9dGC7WlsRBmsWepuNHRxAs3Nw=";

  dontNpmBuild = true;

  nativeBuildInputs = [
    pkgs.makeWrapper
  ];

  postInstall = ''
    mkdir -p $out/share/agents/skills
    ln -s $out/lib/node_modules/rea-agents/skills/reverse-engineer-anything $out/share/agents/skills/reverse-engineer-anything

    substituteInPlace $out/lib/node_modules/rea-agents/dist/application/ClientRegistrationStatus.js \
      --replace-fail 'resolve(command[0] ?? "") === currentCommandPath' \
                     '(resolve(command[0] ?? "") === currentCommandPath || (command[0] ?? "").endsWith("/" + PRODUCT_IDENTITY.cliBinary))'

    for bin in $out/bin/rea $out/bin/rea-agents; do
      wrapProgram "$bin" \
        --set-default GHIDRA_INSTALL_DIR "${pkgs.ghidra}/lib/ghidra" \
        --set-default JAVA_HOME "${pkgs.jdk.home}" \
        --set-default REA_WABT_BIN_DIRECTORY "${pkgs.wabt}/bin" \
        --set-default REA_TSHARK_COMMAND "${pkgs.wireshark-cli}/bin/tshark" \
        --set-default REA_SIGROK_COMMAND "${pkgs.sigrok-cli}/bin/sigrok-cli" \
        --prefix PATH : ${
          lib.makeBinPath [
            pkgs.ghidra
            pkgs.jdk
            pythonWithPwntools
            pkgs.wabt
            pkgs.jadx
            pkgs.android-tools
            pkgs.wireshark-cli
            pkgs.sigrok-cli
            pkgs.binwalk
            pkgs.unblob
            pkgs.mitmproxy
            pkgs.gdb
          ]
        }
    done
  '';

  passthru = {
    skill = "${placeholder "out"}/lib/node_modules/rea-agents/skills/reverse-engineer-anything";
  };

  meta = {
    description = "Reverse engineer anything with agents, from app behavior down to native binaries";
    homepage = "https://github.com/morluto/rea";
    license = lib.licenses.mit;
    mainProgram = "rea";
    platforms = lib.platforms.unix;
  };
}
