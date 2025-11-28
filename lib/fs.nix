# Filesystem utilities
# Helpers for scanning directories, importing modules, etc.
{ lib }:
{
  # Scan a directory and return paths to all importable Nix modules
  # Returns paths to:
  #   - All directories (assumed to have default.nix)
  #   - All .nix files except default.nix
  #
  # Usage:
  #   imports = lib.fs.scanPaths ./modules;
  #   # Returns: [ ./modules/foo ./modules/bar.nix ./modules/baz ]
  scanPaths =
    path:
    builtins.map (f: (path + "/${f}")) (
      builtins.attrNames (
        lib.attrsets.filterAttrs (
          name: type:
          (type == "directory") || ((name != "default.nix") && (lib.strings.hasSuffix ".nix" name))
        ) (builtins.readDir path)
      )
    );

  # Scan a directory and return just the filenames (not full paths)
  # Useful when you need to import with custom logic
  #
  # Usage:
  #   files = lib.fs.scanNames ./modules;
  #   # Returns: [ "foo" "bar.nix" "baz" ]
  scanNames =
    path:
    builtins.attrNames (
      lib.attrsets.filterAttrs (
        name: type:
        (type == "directory") || ((name != "default.nix") && (lib.strings.hasSuffix ".nix" name))
      ) (builtins.readDir path)
    );

  # Scan and import all modules from a directory
  # Each module receives the provided args
  #
  # Usage:
  #   modules = lib.fs.importAll ./modules { inherit pkgs; };
  importAll =
    path: args:
    builtins.map (f: import (path + "/${f}") args) (
      builtins.attrNames (
        lib.attrsets.filterAttrs (
          name: type:
          (type == "directory") || ((name != "default.nix") && (lib.strings.hasSuffix ".nix" name))
        ) (builtins.readDir path)
      )
    );

  # Scan directory, import all modules, and merge their attrsets
  # Perfect for packages/ and overrides/ patterns
  #
  # Usage:
  #   allPackages = lib.fs.importAndMerge ./packages { inherit pkgs; };
  importAndMerge =
    path: args:
    let
      files = builtins.attrNames (
        lib.attrsets.filterAttrs (
          name: type:
          (type == "directory") || ((name != "default.nix") && (lib.strings.hasSuffix ".nix" name))
        ) (builtins.readDir path)
      );
      imported = builtins.map (f: import (path + "/${f}") args) files;
    in
    lib.foldl' lib.recursiveUpdate { } imported;

  # Scan directory and return attrset of named modules
  # Keys are derived from filenames (without .nix extension)
  # Perfect for NixOS/Home Manager module indices
  #
  # Usage:
  #   modules = lib.fs.scanModules ./. { inherit inputs; };
  #   # Returns: { colors = <module>; gtk-theme = <module>; cursor = <module>; }
  #
  # Combined with default:
  #   lib.fs.scanModules ./. args // { default = ...; }
  scanModules =
    path: args:
    let
      entries = lib.attrsets.filterAttrs (
        name: type:
        (type == "directory") || ((name != "default.nix") && (lib.strings.hasSuffix ".nix" name))
      ) (builtins.readDir path);

      # Convert filename to clean attribute name
      toAttrName =
        name: if lib.strings.hasSuffix ".nix" name then lib.strings.removeSuffix ".nix" name else name;
    in
    lib.mapAttrs' (name: _type: {
      name = toAttrName name;
      value = import (path + "/${name}") args;
    }) entries;
}
