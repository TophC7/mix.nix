# GDK-Proton - GE-Proton with WineGDK (Xbox GDK / Gaming Services stand-in)
#
# Needed by GDK titles that refuse to start without Microsoft Gaming Services,
# e.g. Minecraft Dungeons II (https://github.com/ValveSoftware/Proton/issues/10193).
#
# Usage:
#   Add to programs.steam.extraCompatPackages. The tool lives in the
#   `steamcompattool` output (nixpkgs convention, same as proton-ge-bin).
#   Update with ./update.fish (bumps the release and re-locates the patch).
#
# WineGDK bug patched here (XNetworking.c, HTTPClientProvider GetResult):
#   memcpy(buf, &ctx->securityInformationBuffer, n) copies the context struct
#   instead of the buffer it points to. Titles read that garbage as
#   XNetworkingSecurityInformation: random TLS versions (login errors 0063/0064)
#   and wild pointers (access violations inside XCurl.dll).
#   Fix in place: `mov %rdi,%rdx` (48 89 fa) -> `mov (%rdi),%rdx` (48 8b 17).
#   versions.json pins the DLL before and after, so a mismatched offset fails the build.
#
{ lib, pkgs, ... }:
let
  inherit (pkgs) stdenvNoCC fetchurl;

  versions = lib.importJSON ./versions.json;
  patch = versions.xgameruntime;
  displayTitle = "GDK-Proton";
in
stdenvNoCC.mkDerivation {
  pname = "gdk-proton";
  version = lib.removePrefix "release-" versions.tag;

  src = fetchurl {
    url = "https://github.com/LukasPAH/GDK-Proton-Custom/releases/download/${versions.tag}/${versions.asset}";
    inherit (versions) hash;
  };

  outputs = [
    "out"
    "steamcompattool"
  ];

  buildCommand = ''
    # Match nixpkgs proton-ge-bin: `out` is a breadcrumb, not an installable tool
    echo "$pname belongs in programs.steam.extraCompatPackages, not an environment." > $out

    # Tarball holds one top-level tool dir (entries prefixed with ./)
    mkdir unpack
    tar -C unpack -x -f $src
    mv unpack/*/ $steamcompattool

    dll=$steamcompattool/files/lib/wine/x86_64-windows/xgameruntime.dll
    echo "${patch.originalHash}  $dll" | sha256sum -c --quiet
    printf '\x48\x8b\x17' | dd of=$dll bs=1 seek=${toString patch.offset} conv=notrunc status=none
    echo "${patch.patchedHash}  $dll" | sha256sum -c --quiet

    # Upstream keeps GE's internal name, which collides with proton-ge-bin
    sed -i -r 's|"GE-Proton[^"]*"|"${displayTitle}"|g' $steamcompattool/compatibilitytool.vdf
  '';

  meta = with lib; {
    description = "GE-Proton with WineGDK for Xbox GDK titles";
    homepage = "https://github.com/LukasPAH/GDK-Proton-Custom";
    license = with licenses; [
      bsd3
      lgpl21Plus
    ];
    platforms = [ "x86_64-linux" ];
    maintainers = [ tophc7 ];
  };
}
