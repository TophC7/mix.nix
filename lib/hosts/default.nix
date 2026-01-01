# Host specification library
# Provides types and builders for declarative host configuration
#
# ─────────────────────────────────────────────────────────────
# USAGE
# ─────────────────────────────────────────────────────────────
#
# Basic (use default types):
#   lib.hosts.types.userSpec       # The user specification type
#   lib.hosts.types.hostSpec       # The host specification type
#   lib.hosts.mkHost { ... }       # Build a single NixOS config
#   lib.hosts.mkHosts { ... }      # Build multiple NixOS configs
#
# Composable extensions (via flake-parts mix.hostSpecExtensions):
#   # Extension flakes add modules to the extension list:
#   config.mix.hostSpecExtensions = [
#     ({ lib, ... }: {
#       options.desktop.niri.enable = lib.mkEnableOption "Niri";
#       options.greeter.type = lib.mkOption { type = lib.types.str; };
#     })
#   ];
#
# Building extended types directly:
#   lib.hosts.mkUserSpecType [ ./extensions/email.nix ]
#   lib.hosts.mkHostSpecType [ ./extensions/desktop.nix ]
#
# ─────────────────────────────────────────────────────────────
# EXAMPLE
# ─────────────────────────────────────────────────────────────
#
#   # In your flake using mix.nix:
#   mix = {
#     coreModules = [ ./modules/global/core ];
#     coreHomeModules = [ ./home/global/core ];
#     hostsDir = ./hosts;
#     hostsHomeDir = ./home/hosts;
#
#     # Users defined once
#     users = {
#       toph = {
#         name = "toph";
#         shell = pkgs.fish;
#         home.directory = ./home/users/toph;  # Enables HM
#       };
#     };
#
#     # Hosts reference users by name
#     hosts = {
#       desktop = {
#         user = "toph";  # String reference
#         desktop = "niri";
#       };
#       server = {
#         user = "toph";
#         isServer = true;
#         isMinimal = true;  # Only coreHomeModules
#       };
#     };
#   };
#
{ lib }: lib.fs.importAndMerge ./. { inherit lib; }
