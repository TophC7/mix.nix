{ lib, pkgs, ... }:
let
  inherit (pkgs)
    buildGoModule
    fetchFromGitHub
    pkg-config
    gtk4
    libadwaita
    libgcrypt
    librsvg
    wrapGAppsHook4
    ;

  # db.go file that would normally be downloaded by grabTitles.py
  # This is required for the build and contains title database definitions
  # Run ./update-db.fish to update this file, if ever needed
  db-go = ./db.go;
in
buildGoModule rec {
  pname = "WiiUDownloader";
  version = "3.2";

  src = fetchFromGitHub {
    owner = "Xpl0itU";
    repo = "WiiUDownloader";
    rev = "v${version}";
    hash = "sha256-mCiYRoEwWtDQwQy9gFOAlcnsMyB4I1jW5h6NIIRLjGg=";
  };

  modRoot = "cmd/WiiUDownloader";
  vendorHash = "sha256-V75zyp1SoUiI0Uk+CcxVC90A3wLT7NfK1Y6UDCkH4rc=";

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook4
    pkgs.gobject-introspection
  ];

  buildInputs = [
    gtk4
    libadwaita
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
