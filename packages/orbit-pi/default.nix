# Orbit: native GPUI workbench for the pi coding agent, from the official
# release tarball. The in-app updater disables itself on a read-only store path.
{ lib, pkgs, ... }:
let
  pin = lib.importJSON ./version.json;
  inherit (pin) version;
  inherit (pkgs.stdenv.hostPlatform) system;
  arch = lib.head (lib.splitString "-" system);
in
pkgs.stdenv.mkDerivation {
  pname = "orbit-pi";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://github.com/imrj05/orbit/releases/download/v${version}/orbit-pi-${version}-${arch}-unknown-linux-gnu.tar.gz";
    hash = pin.hashes.${system} or (throw "orbit-pi: unsupported system ${system}");
  };

  nativeBuildInputs = with pkgs; [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = with pkgs; [
    libgcc
    libxcb
    libxkbcommon
  ];

  # GPUI dlopens its GPU and Wayland backends.
  runtimeDependencies = with pkgs; [
    vulkan-loader
    wayland
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r bin share $out/
    runHook postInstall
  '';

  # Orbit's first-run check wants git and node beside pi; the user's own PATH wins.
  postFixup = ''
    wrapProgram $out/bin/orbit-pi --suffix PATH : ${
      lib.makeBinPath [
        pkgs.git
        pkgs.nodejs
      ]
    }
  '';

  meta = {
    description = "Native desktop workbench for the pi coding agent";
    homepage = "https://github.com/imrj05/orbit";
    changelog = "https://github.com/imrj05/orbit/releases/tag/v${version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames pin.hashes;
    mainProgram = "orbit-pi";
  };
}
