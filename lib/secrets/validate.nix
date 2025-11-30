# Git-crypt validation for secrets
# Checks that a file pattern is configured for git-crypt in .gitattributes
#
# Arguments:
#   gitattributesPath - Path to .gitattributes file (required)
#   pattern           - Filename pattern to check for (default: "secrets.nix")
#
# Returns:
#   true if valid, throws with helpful error message otherwise
#
# Usage:
#   lib.secrets.assertGitCrypt {
#     gitattributesPath = ./.gitattributes;
#     pattern = "secrets.nix";
#   }
#   # => true (or throws)
#
{ lib }:

{
  assertGitCrypt =
    {
      gitattributesPath,
      pattern ? "secrets.nix",
    }:
    let
      exists = builtins.pathExists gitattributesPath;
      content = if exists then builtins.readFile gitattributesPath else "";

      # Match pattern with git-crypt filter (handles wildcards, paths, etc.)
      # e.g., "secrets.nix filter=git-crypt diff=git-crypt"
      # e.g., "secrets/*.nix filter=git-crypt diff=git-crypt"
      hasFilter = builtins.match ".*${lib.escapeRegex pattern}[^\n]*filter=git-crypt.*" content != null;
    in
    if !exists then
      throw ''
        mix.nix: .gitattributes not found!

        You're using secrets but haven't configured git-crypt.
        Your secrets could be pushed to git in plain text!

        To set up git-crypt:
          1. git-crypt init
          2. echo '${pattern} filter=git-crypt diff=git-crypt' >> .gitattributes
          3. git-crypt add-gpg-user <YOUR-KEY-ID>

        To skip this check (not recommended):
          lib.secrets.load { path = ./secrets.nix; skipValidation = true; }
      ''
    else if !hasFilter then
      throw ''
        mix.nix: '${pattern}' is not configured for git-crypt!

        Your secrets could be pushed to git in plain text!

        Add to .gitattributes:
          ${pattern} filter=git-crypt diff=git-crypt

        To skip this check (not recommended):
          lib.secrets.load { path = ./secrets.nix; skipValidation = true; }
      ''
    else
      true;
}
