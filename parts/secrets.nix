# Flake-parts module for git-crypt encrypted secrets
#
# This module provides:
#   - `mix.secrets` option: Configure and load secrets
#   - Automatic git-crypt validation (ensures secrets are encrypted)
#   - Loaded secrets available at `config.mix.secrets.loaded`
#
# Usage in your flake.nix:
#   imports = [ inputs.mix-nix.flakeModules.secrets ];
#
#   mix.secrets = {
#     file = ./secrets.nix;
#     gitattributes = ./.gitattributes;
#   };
#
# Then in NixOS/HM modules:
#   config.secrets.myKey  # (wired automatically by hosts module)
#
{
  lib,
  config,
  ...
}:

let
  cfg = config.mix.secrets;

  # Load secrets with validation
  loadedSecrets =
    if cfg.file == null then
      { }
    else
      lib.secrets.load {
        path = cfg.file;
        gitattributes = cfg.gitattributes;
        pattern = cfg.pattern;
        skipValidation = cfg.skipValidation;
      };
in
{
  options.mix.secrets = {
    file = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to the secrets.nix file (should be git-crypt encrypted).
        Set to null to disable secrets.
      '';
      example = lib.literalExpression "./secrets.nix";
    };

    gitattributes = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to .gitattributes file for git-crypt validation.
        Required unless skipValidation is true.
      '';
      example = lib.literalExpression "./.gitattributes";
    };

    pattern = lib.mkOption {
      type = lib.types.str;
      default = "secrets.nix";
      description = ''
        Pattern to match in .gitattributes for git-crypt validation.
        Change this if your secrets file has a different name.
      '';
    };

    skipValidation = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Skip git-crypt validation.
        NOT RECOMMENDED - your secrets could be pushed in plain text!
      '';
    };

    # Read-only: the loaded secrets
    loaded = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      readOnly = true;
      description = ''
        The loaded secrets (read-only).
        Access via config.mix.secrets.loaded or use the secrets module.
      '';
    };
  };

  config = {
    # Expose loaded secrets
    mix.secrets.loaded = loadedSecrets;

    flake = {
      # Expose the flake-parts module for consumers
      flakeModules.secrets = ./secrets.nix;
    };
  };
}
