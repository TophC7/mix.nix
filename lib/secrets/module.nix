# Secrets module generator
# Creates a NixOS/Home Manager module that exposes secrets at config.secrets.*
#
# Arguments:
#   secrets - Attrset of secrets to expose
#
# Returns:
#   A module that defines options.secrets and sets config.secrets
#
# Usage:
#   modules = [ (lib.secrets.mkModule { github.token = "xxx"; }) ];
#   # Then in any module: config.secrets.github.token
#
{ lib }:

{
  # Generate a module that exposes secrets at config.secrets.*
  # Works for both NixOS and Home Manager
  mkModule =
    secrets:
    { lib, ... }:
    {
      options.secrets = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "Freeform secrets from git-crypt encrypted secrets.nix";
      };
      config.secrets = secrets;
    };
}
