{ pkgs, lib, ... }:
pkgs.stdenvNoCC.mkDerivation {
  pname = "monocraft-nerd-fonts";
  version = "4.2.1";

  phases = [ "installPhase" ]; # Removes all phases except installPhase

  src = pkgs.fetchurl {
    url = "https://github.com/IdreesInc/Monocraft/releases/download/v4.2.1/Monocraft-nerd-fonts-patched.ttc";
    sha256 = "67f88ff9e7c6560f6cf60fb062fd353a72f62dc2654462950c65b63ed53d9754";
  };

  # unpackPhase = ":".

  installPhase = ''
    mkdir -p $out/share/fonts/truetype/
    cp -r $src $out/share/fonts/truetype/monocraft-nerd-fonts.ttc
  '';

  meta = with lib; {
    description = "Monocraft Nerd Fonts";
    homepage = "https://github.com/IdreesInc/Monocraft";
    platforms = platforms.all;
  };
}
