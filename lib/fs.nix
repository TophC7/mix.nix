# Filesystem utilities
# Helpers for scanning directories, importing modules, etc.
#
# Naming convention:
#   scan*  = filesystem scan only, returns paths (no import/evaluation)
#   import* = imports and evaluates files with provided args
#
{ lib }:
{
  # Scan directory, import all modules, and merge their attrsets
  # Perfect for lib/ subdirectories that export attrsets
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

  # Resolve paths relative to a base directory
  # Returns a curried function for composability with map
  #
  # Usage:
  #   lib.fs.relativeTo /flake/root "modules/core.nix"
  #   # => /flake/root/modules/core.nix
  #
  #   map (lib.fs.relativeTo /flake/root) [
  #     "modules/core.nix"
  #     "modules/optional/audio.nix"
  #   ]
  #
  relativeTo = basePath: lib.path.append basePath;

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

  # Scan directory and return attrset of paths (no import)
  # Keys are derived from filenames (without .nix extension)
  # Perfect for NixOS/Home Manager module indices where the module
  # system handles importing and calling with { config, lib, pkgs, ... }
  #
  # Usage:
  #   nixosModules = lib.fs.scanAttrs ./.;
  #   # Returns: { oci-stacks = ./oci-stacks.nix; newt = ./newt.nix; }
  scanAttrs =
    path:
    let
      entries = lib.attrsets.filterAttrs (
        name: type:
        (type == "directory") || ((name != "default.nix") && (lib.strings.hasSuffix ".nix" name))
      ) (builtins.readDir path);

      toAttrName =
        name: if lib.strings.hasSuffix ".nix" name then lib.strings.removeSuffix ".nix" name else name;
    in
    lib.mapAttrs' (name: _type: {
      name = toAttrName name;
      value = path + "/${name}";
    }) entries;

  # Import all files and return attrset of evaluated results
  # Keys are derived from filenames (without .nix extension)
  # Each file is imported and called with the provided args
  #
  # Usage:
  #   modules = lib.fs.importAttrs ./. { inherit lib; };
  #   # Returns: { colors = <evaluated>; theme = <evaluated>; }
  importAttrs =
    path: args:
    let
      entries = lib.attrsets.filterAttrs (
        name: type:
        (type == "directory") || ((name != "default.nix") && (lib.strings.hasSuffix ".nix" name))
      ) (builtins.readDir path);

      toAttrName =
        name: if lib.strings.hasSuffix ".nix" name then lib.strings.removeSuffix ".nix" name else name;
    in
    lib.mapAttrs' (name: _type: {
      name = toAttrName name;
      value = import (path + "/${name}") args;
    }) entries;
}
