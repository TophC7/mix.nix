{ lib, pkgs, ... }:
let
  inherit (pkgs)
    buildGoModule
    fetchFromGitHub
    pkg-config
    gtk3
    libgcrypt
    librsvg
    wrapGAppsHook3
    ;

  # db.go file that would normally be downloaded by grabTitles.py
  # This is required for the build and contains title database definitions
  # Run ./update-db.fish to update this file, if ever needed
  db-go = ./db.go;
in
buildGoModule rec {
  pname = "WiiUDownloader";
  version = "2.98";

  src = fetchFromGitHub {
    owner = "Xpl0itU";
    repo = "WiiUDownloader";
    rev = "v${version}";
    hash = "sha256-vLbf0tHumqBetqIoqQ/+foV6HA6b/8GqH2BwOaLVkRA=";
  };

  modRoot = "cmd/WiiUDownloader";
  vendorHash = "sha256-sr6p41U+OQd3uWVRM2g0vQel7vNG1rzddJ2Q/57TTls=";

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook3
  ];

  buildInputs = [
    gtk3
    libgcrypt
    librsvg
  ];

  # Inject the pre-fetched database after buildGoModule copies the fixed
  # vendor tree, keeping database refreshes independent from vendorHash.
  postConfigure = ''
    chmod -R u+w vendor/github.com/Xpl0itU/WiiUDownloader
    cp ${db-go} vendor/github.com/Xpl0itU/WiiUDownloader/db.go
  '';

  # Build flags from the GitHub Actions workflow
  ldflags = [
    "-s"
    "-w"
  ];

  subPackages = [ "." ];

  # Skip tests - they're extremely slow
  doCheck = false;

  # Install desktop file
  postInstall = ''
    mkdir -p $out/share/applications
    cat > $out/share/applications/WiiUDownloader.desktop << EOF
    [Desktop Entry]
    Name=WiiU Downloader
    Comment=Download Wii U games, updates, DLC, and demos from Nintendo's servers
    Exec=${pname}
    Icon=folder-download
    Terminal=false
    Type=Application
    Categories=Game;Utility;
    Keywords=wii;wiiu;nintendo;download;game;
    EOF
  '';

  meta = with lib; {
    description = "GUI application to download Wii U games, updates, DLC, and demos directly from Nintendo's servers";
    homepage = "https://github.com/Xpl0itU/WiiUDownloader";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ ];
    mainProgram = "WiiUDownloader";
    platforms = platforms.linux;
  };
}
