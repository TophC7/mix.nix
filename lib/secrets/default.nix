# Secrets utilities - load, validate, and generate modules for git-crypt secrets
#
# Exports:
#   lib.secrets.load { path; gitattributes; }  # Import secrets file with git-crypt validation
#   lib.secrets.mkModule secrets               # Generate NixOS/HM module exposing config.secrets.*
#   lib.secrets.assertGitCrypt { }             # Validate git-crypt is configured in .gitattributes
#
{ lib }:

lib.fs.importAndMerge ./. { inherit lib; }
