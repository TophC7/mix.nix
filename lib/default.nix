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
#
# No infinite recursion risk: our modules only use base nixpkgs lib functions,
# never each other during definition.
baseLib:

baseLib.extend (
  final: prev: {
    # Filesystem utilities
    fs = import ./fs.nix { lib = final; };

    # Host specification and builder utilities
    hosts = import ./hosts { lib = final; };

    # Desktop / Aesthetic utilities
    desktop = import ./desktop { lib = final; };
  }
)
