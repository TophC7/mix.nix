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
# Extended (add your own options):
#   lib.hosts.mkUserSpec {
#     options.email = lib.mkOption { type = lib.types.str; };
#     options.gpgKey = lib.mkOption { type = lib.types.nullOr lib.types.str; };
#   }
#
#   lib.hosts.mkHostSpec {
#     options.mounts.tank = lib.mkOption { type = lib.types.bool; default = false; };
#     options.network.vpn = lib.mkOption { type = lib.types.bool; default = false; };
#   }
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
