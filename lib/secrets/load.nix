# Load and validate secrets from a git-crypt encrypted file
#
# Imports a secrets file after validating git-crypt is configured.
# Throws helpful error if .gitattributes is missing or misconfigured.
#
# Arguments:
#   path           - Path to the secrets.nix file (required)
#   gitattributes  - Path to .gitattributes for validation (required unless skipValidation)
#   pattern        - Pattern to match in .gitattributes (default: "secrets.nix")
#   skipValidation - Skip git-crypt check (default: false, not recommended)
#
# Returns:
#   The imported secrets attrset
#
# Usage:
#   lib.secrets.load {
#     path = ./secrets.nix;
#     gitattributes = ./.gitattributes;
#   }
#   # => { github.token = "..."; wifi.home = "..."; }
#
{ lib }:
{
  load =
    {
      # Path to the secrets.nix file
      path,
      # Path to .gitattributes (required unless skipValidation = true)
      gitattributes ? null,
      # Pattern to match in .gitattributes (default: "secrets.nix")
      pattern ? "secrets.nix",
      # Skip git-crypt validation (not recommended)
      skipValidation ? false,
    }:
    let
      # Validate git-crypt is configured (unless skipped)
      validated =
        if skipValidation then
          true
        else if gitattributes == null then
          throw ''
            mix.nix secrets: gitattributes path required!

            Either provide the path to .gitattributes:
              lib.secrets.load {
                path = ./secrets.nix;
                gitattributes = ./.gitattributes;
              }

            Or explicitly skip validation (not recommended):
              lib.secrets.load {
                path = ./secrets.nix;
                skipValidation = true;
              }
          ''
        else
          lib.secrets.assertGitCrypt {
            gitattributesPath = gitattributes;
            inherit pattern;
          };

      # Import the secrets file
      secrets = import path;
    in
    # Force validation before returning secrets
    assert validated;
    secrets;
}
