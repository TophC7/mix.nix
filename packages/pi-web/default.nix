{
  lib,
  pkgs,
  ...
}:
# The npm tarball ships the prebuilt `.next`; building from source would need
# network for next/font/google. It carries no lockfile, so the tag's is used.
pkgs.buildNpmPackage (finalAttrs: {
  pname = "pi-web";
  version = "0.12.2";

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@agegr/pi-web/-/pi-web-${finalAttrs.version}.tgz";
    hash = "sha256-Fq/g7h/2O5VCmtc4AtE+U6L4MXJGQT7Ri5L3s2/YbGo=";
  };

  # The npm-deps fetcher reruns postPatch without this derivation's attrs, so
  # the lockfile is interpolated rather than read from `$lockfile`.
  postPatch = "cp ${
    pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/agegr/pi-web/v${finalAttrs.version}/package-lock.json";
      hash = "sha256-ps/E5YrpnkuwQE/P9g0O3SpoubzlXz+WO5ljIChbfBc=";
    }
  } package-lock.json";

  npmDepsHash = "sha256-WWmrAjPrN1Nk2NrTJ9GFEBXp7Y1y/RZjMZxnJSQcNjY=";

  dontNpmBuild = true;

  # node-gyp builds node-pty.
  nativeBuildInputs = [ pkgs.python3 ];

  # The launcher rotates Next's preview secrets in `.next` on every start, which
  # a read-only store refuses; rotate once here so this build's differ from the
  # ones published on npm.
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
})
