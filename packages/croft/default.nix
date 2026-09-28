{
  lib,
  pkgs,
  ...
}:
pkgs.rustPlatform.buildRustPackage rec {
  pname = "croft";
  version = "0.1.942";

  src = pkgs.fetchFromGitHub {
    owner = "vitali87";
    repo = "croft";
    rev = "v${version}";
    hash = "sha256-CEf7Kfu4B0R7xdO3K7t0KflbqAbUaNmTFMVPMpoVODU=";
  };

  cargoHash = "sha256-H4j7W8zvMa3o2MR7RKvZz2aMUFFPN9RFI9UeDFgtHJ0=";

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
