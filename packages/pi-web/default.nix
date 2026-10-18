{
  lib,
  pkgs,
  ...
}:
# Build the tophc7/pi-web fork's store-backed attachments from source, replacing
# Google Fonts with nixpkgs Noto Sans Mono so the build runs offline.
pkgs.buildNpmPackage {
  pname = "pi-web";
  version = "0.12.2-attachments";

  src = pkgs.fetchFromGitHub {
    owner = "tophc7";
    repo = "pi-web";
    rev = "ee2677a7efcf3d1916257ccd98dbf0abb87ada18";
    hash = "sha256-OYEjuVO6xZEeTwY7BbaiYsF+posfAlBN5zKiY10F6/c=";
  };

  patches = [ ./offline-font.patch ];
  postPatch = "cp ${pkgs.noto-fonts}/share/fonts/noto/NotoSansMono.ttf app/NotoSansMono.ttf";

  npmDepsHash = "sha256-WWmrAjPrN1Nk2NrTJ9GFEBXp7Y1y/RZjMZxnJSQcNjY=";
  env.NEXT_TELEMETRY_DISABLED = "1";

  # node-gyp builds node-pty.
  nativeBuildInputs = [ pkgs.python3 ];

  # The launcher rotates Next's preview secrets in `.next` on every start, which
  # a read-only store refuses; rotate once here so each build has distinct secrets.
  postInstall = ''
    node -e 'process.exit(require("./bin/rotate-preview-secrets").rotatePreviewSecrets(process.argv[1]).ok ? 0 : 1)' \
      $out/lib/node_modules/@agegr/pi-web/.next
  '';

  meta = {
    description = "Web UI for the pi coding agent";
    homepage = "https://github.com/agegr/pi-web";
    license = lib.licenses.mit;
    mainProgram = "pi-web";
    platforms = lib.platforms.linux;
  };
}
