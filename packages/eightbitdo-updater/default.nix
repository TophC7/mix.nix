{ lib, pkgs, ... }:
let
  inherit (pkgs) fetchurl unzip stdenv;

  # 8BitDo Ultimate Software
  updaterZip = fetchurl {
    url = "https://support.8bitdo.com/bd-uploads/files/ultimate_soft/8BitDo_Ultimate_Software_V2_Windows_V1.34.zip";
    sha256 = "sha256-yZ4OEwPHc8mwJgKpvLXNSQ1pKGMoK67dBv0toOvVuQA=";
  };

  # Extract the updater from the ZIP
  updaterSrc = stdenv.mkDerivation {
    name = "8bitdo-ultimate-software-extracted";
    src = updaterZip;
    nativeBuildInputs = [ unzip ];
    unpackPhase = ''
      unzip $src
    '';
    installPhase = ''
      mkdir -p $out
      # Copy ALL files from the extracted subdirectory (exe needs its DLLs and configs)
      cp -r 8BitDo_Ultimate_Software_V2_Windows_V1.34/* $out/
    '';
  };
in
lib.desktop.mkWineApp pkgs {
  name = "8bitdo-updater";
  is64bits = false;
  wine = pkgs.wineWow64Packages.waylandFull;
  executable = "${updaterSrc}/8BitDo Ultimate Software V2.exe";

  # Let winetricks handle fonts
  tricks = [
    "corefonts" # Basic Windows fonts
  ];

  # Additional setup after winetricks
  firstrunScript = ''
    # Disable SDL mode in winebus (prevents firmware updater from accessing device)
    # This is done via registry: HKLM\System\CurrentControlSet\Services\winebus
    cat >> "$WINEPREFIX/system.reg" << 'EOF'

    [System\\CurrentControlSet\\Services\\winebus]
    "Enable SDL"=dword:00000000
    EOF

    echo "8BitDo Updater setup complete!"
    echo "Make sure your controller is in bootloader mode (press LB+RB and connect via USB)"
  '';
}
