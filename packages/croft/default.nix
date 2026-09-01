{
  lib,
  pkgs,
  ...
}:
pkgs.rustPlatform.buildRustPackage rec {
  pname = "croft";
  version = "0.1.736";

  src = pkgs.fetchFromGitHub {
    owner = "vitali87";
    repo = "croft";
    rev = "v${version}";
    hash = "sha256-meba/k9QUMUMuC99okRNcXvXLLc8KagnsffBhTO+1E4=";
  };

  cargoHash = "sha256-wNMD8ENSkdFlUwBuQKDQpM2p8a5VcK3dQ1M1OnL+HF8=";

  nativeBuildInputs = with pkgs; [
    pkg-config
  ];

  # Unit tests spawn interactive terminal subprocesses and impure /bin/* tools
  doCheck = false;

  meta = {
    description = "VSCode-style TUI written in Rust";
    homepage = "https://github.com/vitali87/croft";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ ];
    mainProgram = "croft";
    platforms = lib.platforms.unix;
  };
}
