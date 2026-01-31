# Proton-CachyOS - Pre-built Proton with CachyOS optimizations
#
# Provides variants for different CPU microarchitectures:
#   pkgs.proton-cachyos      - x86-64-v3 (default, AVX2 - most modern CPUs)
#   pkgs.proton-cachyos-v4   - x86-64-v4 (AVX-512 - high-end CPUs)
#
# Usage:
#   Add to Steam's compatibility tools directory or use with programs.steam
#
{ lib, pkgs, ... }:
let
  inherit (pkgs) stdenv fetchurl;

  # Factory function for creating proton variants
  mkProtonCachyos =
    {
      variant, # "v3" or "v4"
      versionFile,
      displayTitle ? "Proton-CachyOS ${lib.strings.toUpper variant}",
    }:
    let
      versions = lib.importJSON versionFile;
      tagName = "cachyos-${versions.base}-${versions.release}-slr";
      fileName = "proton-cachyos-${versions.base}-${versions.release}-slr-x86_64_${variant}.tar.xz";
    in
    stdenv.mkDerivation {
      pname = "proton-cachyos-${variant}";
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
        description = "CachyOS Proton build with optimizations for x86-64-${variant}";
        homepage = "https://github.com/CachyOS/proton-cachyos";
        license = licenses.bsd3;
        platforms = [ "x86_64-linux" ];
        maintainers = [ tophc7 ];
      };
    };

  # Create variants
  v3 = mkProtonCachyos {
    variant = "v3";
    versionFile = ./versions-v3.json;
    displayTitle = "Proton-CachyOS";
  };

  v4 = mkProtonCachyos {
    variant = "v4";
    versionFile = ./versions-v4.json;
    displayTitle = "Proton-CachyOS v4";
  };
in
# Export v3 as default, with v4 as attribute
v3 // { inherit v4; }
