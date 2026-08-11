# Proton-CachyOS - Pre-built Proton with CachyOS optimizations
#
# Provides upstream's supported x86-64 variants:
#   pkgs.proton-cachyos      - baseline x86-64 (default)
#   pkgs.proton-cachyos.v3   - x86-64-v3 (AVX2)
#
# Usage:
#   Add to Steam's compatibility tools directory or use with programs.steam
#
{ lib, pkgs, ... }:
let
  inherit (pkgs) stdenvNoCC fetchurl;

  mkProtonCachyos =
    {
      variant ? null,
      versionFile,
      displayTitle,
    }:
    let
      versions = lib.importJSON versionFile;
      tagName = "cachyos-${versions.base}-${versions.release}-slr";
      architecture = "x86_64" + lib.optionalString (variant != null) "_${variant}";
      fileName = "proton-cachyos-${versions.base}-${versions.release}-slr-${architecture}.tar.xz";
    in
    stdenvNoCC.mkDerivation {
      pname = "proton-cachyos" + lib.optionalString (variant != null) "-${variant}";
      version = "${versions.base}.${versions.release}";

      src = fetchurl {
        url = "https://github.com/CachyOS/proton-cachyos/releases/download/${tagName}/${fileName}";
        inherit (versions) hash;
      };

      buildCommand = ''
        mkdir -p $out/bin
        tar -C $out/bin --strip=1 -x -f $src

        # Set consistent display name in Steam
        sed -i -r 's|"proton-cachyos-[^"]*"|"${displayTitle}"|g' $out/bin/compatibilitytool.vdf
        sed -i -r 's|"display_name"[[:space:]]*"[^"]*"|"display_name" "${displayTitle}"|' $out/bin/compatibilitytool.vdf
      '';

      meta = with lib; {
        description = "CachyOS Proton build for ${lib.replaceStrings [ "_" ] [ "-" ] architecture}";
        homepage = "https://github.com/CachyOS/proton-cachyos";
        license = licenses.bsd3;
        platforms = [ "x86_64-linux" ];
        maintainers = [ tophc7 ];
      };
    };

  baseline = mkProtonCachyos {
    versionFile = ./versions.json;
    displayTitle = "Proton-CachyOS";
  };

  v3 = mkProtonCachyos {
    variant = "v3";
    versionFile = ./versions-v3.json;
    displayTitle = "Proton-CachyOS x86-64-v3";
  };
in
baseline // { inherit v3; }
