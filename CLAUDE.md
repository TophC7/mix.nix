# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

**mix.nix** is a library of Nix utilities designed to simplify NixOS and Home Manager configurations. It provides reusable patterns, type definitions, and builder functions that reduce boilerplate and enforce consistency across flake-based configurations.

The library is meant to be consumed by other flakes via `inputs.mix-nix`.

## Design Philosophy

### Core Principles

1. **Directory Auto-Discovery Over Explicit Lists**
   - Configuration modules live in directories and are auto-imported
   - No manual `imports = [ ./foo.nix ./bar.nix ]` lists
   - Adding a file to a directory automatically includes it

2. **Declarative Specs Describe "What", Not "How"**
   - Specifications define properties and identity
   - Implementation details go in directories
   - Specs should be minimal - avoid options for things directories/consumers of mix.nix handle

3. **Convention Over Configuration**
   - Consistent directory structures across the library
   - Predictable patterns reduce cognitive load
   - Follow established Nix conventions

4. **Extensibility Via Factory Functions**
   - Base types stay minimal
   - Factory functions (`mkXxxSpec`) allow consumers to add custom options
   - Uses `freeformType` for arbitrary extensions when appropriate

5. **Library, Not Configuration**
   - mix.nix provides utilities, not opinionated configs
   - Everything should be generic and reusable
   - No host-specific or user-specific code

## Architecture

```
lib/
├── default.nix      # Entry point - extends nixpkgs lib
├── fs.nix           # Filesystem utilities
├── desktop/         # Desktop utilities (colors, wine, theming)
├── hosts/           # Host/user management utilities
└── infra/           # Infrastructure utilities (containers, etc.)
modules/
├── nixos/           # Reusable NixOS modules
│   ├── oci-stacks.nix   # OCI container stack orchestration
│   └── ...
└── home/            # Reusable Home Manager modules
parts/
└── hosts.nix        # Flake-parts integration
```

### Library Extension Pattern

mix.nix extends `nixpkgs.lib` so all utilities are available under a unified `lib`:

```nix
lib = (import ./lib) nixpkgs.lib;

# Now available:
lib.fs.*        # Filesystem utilities
lib.hosts.*     # Host management
lib.desktop.*   # Desktop utilities
lib.infra.*     # Infrastructure utilities
```

### Flake-Parts Integration

When using flake-parts, the extended lib **must** be passed via `specialArgs` in `mkFlake`:

```nix
# flake.nix
outputs = inputs@{ flake-parts, ... }:
  let
    # Create extended lib BEFORE mkFlake
    lib = (import ./lib) inputs.nixpkgs.lib;
  in
  flake-parts.lib.mkFlake {
    inherit inputs;
    specialArgs = { inherit lib; };  # Highest priority, cannot be shadowed
  } { ... };
```

**Why not `_module.args`?** When a flake-parts module has `{ lib, ... }:` in its
function signature, flake-parts provides its default `lib` (from nixpkgs-lib)
before `_module.args` can override it. `specialArgs` has highest priority and
cannot be shadowed by function arguments.

**For non-flake-parts imports** (like `modules/nixos/default.nix`), pass `lib` explicitly:
```nix
nixosModules = import ../modules/nixos { inherit inputs lib; };
```

### Auto-Discovery Pattern

All lib subdirectories use `lib.fs.importAndMerge` for auto-discovery:

```nix
# lib/desktop/default.nix
{ lib }:
lib.fs.importAndMerge ./. { inherit lib; }
```

This means adding a new `.nix` file to a directory automatically exports its attributes.

### lib/ vs modules/

**lib/** and **modules/** serve different purposes:

| Aspect             | lib/                               | modules/                                             |
| ------------------ | ---------------------------------- | ---------------------------------------------------- |
| **Purpose**        | Functions and utilities            | User-facing options                                  |
| **Consumer usage** | Called in expressions              | Imported, then options are set                       |
| **Provides**       | Helpers, builders, data transforms | `options.*` definitions with defaults and assertions |

**When to use lib/:**
- Pure functions (no side effects, no `config`)
- Utilities that transform or query data
- Builders that generate derivations or config fragments
- Internal type definitions used by modules

**When to use modules/:**
- Defining options that consumers set directly in their configs
- Anything with `options = { ... }` and `config = { ... }`
- Assertions and validations on user-provided values
- Features consumers enable via `imports = [ ... ]`

**Pattern:** When a feature needs both, the module defines the option and the lib provides utilities for working with the data:
```nix
# Consumer imports the module, sets the option
imports = [ inputs.mix-nix.homeManagerModules.someFeature ];
someFeature = { ... };

# Other modules use lib utilities to work with that data
lib.desktop.someFeature.transform config.someFeature
```

## Common Development Commands

```bash
# Check flake validity
nix flake check

# Show flake outputs
nix flake show

# Test in a consumer flake
cd ../dot.nix && nix flake check
```

## Development Guidelines

### Adding New Utilities

1. Determine which namespace it belongs to (`fs`, `desktop`, `hosts`, `infra`, or new)
2. Create a `.nix` file in the appropriate directory
3. Export an attrset - it will be auto-merged
4. Add documentation in the file header

### When Designing Options/Types

Ask: "Should this be configurable, or should it follow convention?"

- Prefer convention when a sensible default exists
- Only add options when flexibility is genuinely needed
- Keep specs minimal - directories handle implementation details

### Code Patterns

**File headers should document usage:**
```nix
# Brief description of what this module provides
#
# Usage:
#   lib.namespace.functionName { ... }
#
{ lib }:
{ ... }
```

**Consistent argument patterns:**
```nix
{ lib }:           # For lib utilities
{ lib, pkgs }:     # When packages are needed
{ inputs, ... }:   # For flake-parts modules
```

### Shell Standards

- Prioritize Fish shell for all scripts and examples
- Use `${lib.getExe pkgs.fish}` for shebangs

## Key Utilities

### lib.fs

Filesystem utilities for auto-discovery:
- `scanPaths` - Returns paths to all importable modules in a directory
- `scanNames` - Returns just filenames (not full paths)
- `scanAttrs` - Returns attrset of `{ name = ./path; }` for module indices
- `importAndMerge` - Import all files and merge their attrsets
- `importAttrs` - Import all and return attrset of evaluated results
- `relativeTo` - Curried path resolver for composability with map

### lib.desktop

Desktop environment utilities:
- Color palette generation
- Wine application wrappers
- Theming helpers

### lib.hosts

Host and user management:
- `lib.hosts.types.userSpec` - User specification type
- `lib.hosts.types.hostSpec` - Host specification type
- `lib.hosts.modules.baseUserSpec` - Base user module (for submoduleWith imports)
- `lib.hosts.modules.baseHostSpec` - Base host module (for submoduleWith imports)
- `lib.hosts.mkUserSpecType` - Build userSpec type with extension modules
- `lib.hosts.mkHostSpecType` - Build hostSpec type with extension modules
- `lib.hosts.mkHosts` - Build `nixosConfigurations` from specs

**Namespace convention**: Types live under `.types.*`, base modules under `.modules.*`, builder functions at top level.

**Composable Extensions**: To extend hostSpec/userSpec from other flakes, use `mix.hostSpecExtensions` and `mix.userSpecExtensions`. This allows multiple extension flakes (like arroz.nix, play.nix) to add options without conflicts.

**Extension: arroz.nix** - For desktop environment and greeter configuration options (desktop DE type, auto-login, etc.), use the [arroz.nix](https://github.com/toph/arroz.nix) extension which adds these via `mix.hostSpecExtensions`.

### lib.infra

Infrastructure utilities:
- `lib.infra.containers.serviceDefaults` - Default systemd service config for containers (restart policies, timing)

Used by the `oci-stacks` module but can also be applied directly to container services.

## Important Notes

1. **This is a library** - Provides utilities consumed by other flakes
2. **No hardcoded values** - Everything should be parameterized
3. **Minimal dependencies** - Only nixpkgs, optionally home-manager
4. **Type safety** - Use proper Nix types and validation
5. **Documentation in code** - Comment headers explain usage

## Troubleshooting

### Debugging Principles

**Always verify the foundation before building on top of it.** For exampe when you see an error like `attribute 'foo' missing`, don't assume complex causes (module system, evaluation order, etc.) - first verify the attribute actually exists.

### Example Debug Commands

```bash
# Verify lib extension works and inspect structure
nix eval --impure --expr '
  let lib = (import ./lib) (import <nixpkgs> {}).lib;
  in builtins.attrNames lib.infra
'

# Check if a specific path exists
nix eval --impure --expr '
  let lib = (import ./lib) (import <nixpkgs> {}).lib;
  in lib.infra.containers.serviceDefaults
'

# Test a module in isolation
nix repl
> :lf .
> lib.fs.scanPaths ./modules/nixos
```

### Common Issues

1. **"attribute 'X' missing" in lib.namespace.X**
   - First verify with `nix eval` that the attribute actually exists
   - Check the file exports the right structure (e.g., `{ containers = { ... }; }` not just `{ ... }`)
   - Remember: `importAndMerge` flattens - what you export at top level becomes the namespace

2. **Module receives wrong lib**
   - Consumer must pass extended lib via `specialArgs` in `nixosSystem`
   - Verify with: `nix eval .#nixosConfigurations.hostname.config._module.args.lib.infra`

3. **Infinite recursion in modules**
   - Usually caused by accessing `config` in a way that forces eager evaluation
   - Use `lib.mkMerge` with separate config paths, not `mapAttrsToList` on `config`

### Lib Namespace Structure

When adding to lib namespaces, remember that `importAndMerge` merges top-level attributes:

```nix
# lib/infra/containers.nix
{ lib }: {
  containers = {        # <-- This becomes lib.infra.containers
    serviceDefaults = { ... };
  };
}

# NOT this (would become lib.infra.serviceDefaults):
{ lib }: {
  serviceDefaults = { ... };  # Wrong - no containers namespace
}
```