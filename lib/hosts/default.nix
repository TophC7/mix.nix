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
# API versions (apiVersion here, mix.apiVersion in flake-parts; only 1 or 2):
#   1 - default, deprecated: locations from coreModules, coreHomeModules, hostsDir,
#       hostsHomeDir, usersHomeDir; HM only when a user profile is found;
#       isMinimal limits HM to secrets + coreHomeModules. Warns once. No
#       lib.features; extends rejected (even null).
#       A future breaking release makes omitted/1 an error (never silently v2).
#   2 - opt-in, fixed layout under inputs.self (<x>/ = <x>/default.nix, else <x>.nix):
#         hosts/<host>/             host NixOS; its home/ or home.nix is host HM,
#                                   imported into the enrolled user after the profile
#         modules/core/             NixOS for every host; its home/ or home.nix is
#                                   added to home-manager.sharedModules
#         modules/users/<user>/     HM profile; enrolls the user ({ } = shared only)
#         modules/features/<name>/  nixos.nix / home.nix via lib.features [ "<name>" ]
#       Optional extends = <root>: names resolve locally, then there; its core
#       applies first. HM integration whenever the HM input exists; no isMinimal
#       (declare your own flags); v1 locations rejected even when [] / null. Directory roots
#       (host, core) must not lib.fs.scanPaths ./. (it would import home/ into NixOS).
#   Migration: README "API Versions & Migration".
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
#   # In your flake using mix.nix (layout: hosts/, modules/{core,features,users}/):
#   mix = {
#     apiVersion = 2;
#     # Users defined once
#     users = {
#       toph = {
#         name = "toph";
#         shell = "fish";
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
#       };
#     };
#   };
#
{ lib }: lib.fs.importAndMerge ./. { inherit lib; }
