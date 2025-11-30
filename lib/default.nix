# Extend nixpkgs lib with our custom library functions
#
# This is THE entry point for this library. Always use lib.extend pattern.
#
# Usage:
#   lib = (import ./lib) nixpkgs.lib;
#
# You get:
#   - All of nixpkgs lib (lib.mkOption, lib.types, lib.attrsets, etc.)
#   - lib.fs.*       - filesystem utilities (scanPaths, importAndMerge)
#   - lib.infra.*    - infrastructure utilities (containers, networking)
#   - lib.desktop.*  - desktop utilities (colors, theming)
#   - lib.secrets.*  - secrets utilities
#
# No infinite recursion risk: our modules only use base nixpkgs lib functions,
# never each other during definition.
baseLib:

baseLib.extend (
  final: _: {
    # Filesystem utilities
    fs = import ./fs.nix { lib = final; };

    # Host specification and builder utilities
    hosts = import ./hosts { lib = final; };

    # Desktop / Aesthetic utilities
    desktop = import ./desktop { lib = final; };

    # Secrets utilities (types for gitignored secrets)
    secrets = import ./secrets { lib = final; };

    # Standalone flake builder (for non-flake-parts users)
    inherit (import ./mkFlake.nix { lib = final; }) mkFlake;
  }
)
