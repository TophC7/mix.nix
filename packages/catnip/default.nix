# catnip — W&B containerized coding agent sessions CLI
#
# Prebuilt Go binary from GitHub releases.
# Provides `catnip serve` (HTTP server) and `catnip run` (container mode).
{
  lib,
  pkgs,
  ...
}:
let
  version = "0.12.1";
in
pkgs.stdenv.mkDerivation {
  pname = "catnip";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://github.com/wandb/catnip/releases/download/v${version}/catnip_${version}_linux_amd64.tar.gz";
    hash = "sha256-tEYvPnhoWM3aeG5u/tTL7plchg8ijIq6hTx7D5Bav+A=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [ pkgs.autoPatchelfHook ];
  buildInputs = [ pkgs.stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 catnip "$out/bin/catnip"
    runHook postInstall
  '';

  meta = {
    description = "W&B Catnip – containerized coding agent sessions";
    homepage = "https://github.com/wandb/catnip";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "catnip";
  };
}
