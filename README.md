<p align="left">
  <h1><img src="public/nix.svg" height=30 /> mix.nix</h1>
  <p >A NixOS library for declarative host management, theming, and desktop configuration</p>
  <a href="https://deepwiki.com/TophC7/dot.nix"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki"></a>
</p>

---

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Home Manager Modules](#home-manager-modules)
  - [theme](#theme)
  - [monitors](#monitors)
  - [fastfetch](#fastfetch)
  - [nautilus](#nautilus)
- [Flake-Parts Modules](#flake-parts-modules)
  - [hosts](#hosts)
  - [secrets](#secrets)
  - [modules](#modules)
  - [overlays](#overlays)
  - [packages](#packages)
  - [devshell](#devshell)
- [Library Reference](#library-reference)
- [Real-World Example](#real-world-example)
- [Design Philosophy](#design-philosophy)
- [Contributing](#contributing)

---

## Overview

**mix.nix** is a library of Nix utilities designed to simplify NixOS and Home Manager configurations. It provides reusable patterns, type definitions, and builder functions that reduce boilerplate and enforce consistency across flake-based configurations.

The library offers:
- **Declarative host/user management** - Define users once, reference them across multiple hosts, auto-generate `nixosConfigurations`
- **Wallpaper-based theming** - Generate Material You color schemes from your wallpaper using matugen
- **Multi-monitor configuration** - Declare monitor layouts once, use everywhere
- **Git-crypt secrets integration** - Load encrypted secrets with validation to prevent accidental plaintext commits
- **Directory auto-discovery** - Drop files in directories, they're automatically imported

mix.nix is consumed by other flakes via `inputs.mix-nix` and extends `nixpkgs.lib` with custom utilities.

---

## Quick Start

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    mix-nix.url = "github:tophc7/mix.nix";
    # mix-nix follows nixpkgs automatically
  };

  outputs = { nixpkgs, mix-nix, ... }: {
    # Import a Home Manager module directly
    homeConfigurations.myuser = home-manager.lib.homeManagerConfiguration {
      # ...
      modules = [
        mix-nix.homeManagerModules.theme
        {
          theme = {
            enable = true;
            image = ./wallpaper.jpg;
            base16.generate = true;  # Generate colors from wallpaper
          };
        }
      ];
    };
  };
}
```

See [Installation](#installation) for full setup with flake-parts.

---

## Installation

### With Flakes + flake-parts (Recommended)

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager.url = "github:nix-community/home-manager";

    mix-nix = {
      url = "github:tophc7/mix.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, mix-nix, ... }:
    flake-parts.lib.mkFlake {
      inherit inputs;
      specialArgs = { lib = mix-nix.lib; };
    } {
      imports = [ mix-nix.flakeModules.default ];

      # Or import selectively:
      # imports = [
      #   mix-nix.flakeModules.hosts
      #   mix-nix.flakeModules.secrets
      #   mix-nix.flakeModules.modules
      # ];

      systems = [ "x86_64-linux" "aarch64-linux" ];

      mix = {
        # Your host and user configurations...
      };
    };
}
```

> **Why `specialArgs`?** The extended `lib` (with `lib.hosts`, `lib.secrets`, etc.) must be passed via `specialArgs` so flake-parts modules can access it. `specialArgs` has highest priority and cannot be shadowed.

### With Flakes (without flake-parts)

Use `lib.mkFlake` for the same declarative host management without flake-parts:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";

    mix-nix = {
      url = "github:tophc7/mix.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, mix-nix, home-manager, ... }@inputs:
    mix-nix.lib.mkFlake {
      inherit inputs;
      homeManager = home-manager;

      coreModules = [ ./modules/core ];
      coreHomeModules = [
        ./home/core
        mix-nix.homeManagerModules.theme
        mix-nix.homeManagerModules.monitors
      ];

      hostsDir = ./hosts;
      hostsHomeDir = ./home/hosts;

      # Optional: git-crypt encrypted secrets
      secrets = {
        file = ./secrets.nix;
        gitattributes = ./.gitattributes;
      };

      users.myuser = {
        name = "myuser";
        shell = nixpkgs.legacyPackages.x86_64-linux.fish;
        home.directory = ./home/users/myuser;
      };

      hosts.desktop = {
        user = "myuser";
        desktop = "niri";
      };
    };
    # Returns: { nixosConfigurations.desktop = <nixosSystem>; }
}
```

### Without Flakes (using getFlake)

For non-flake configurations, use `builtins.getFlake` to access flake outputs:

```nix
# configuration.nix or home.nix
let
  mix-nix = builtins.getFlake "github:tophc7/mix.nix";
  # Or pin to a specific commit:
  # mix-nix = builtins.getFlake "github:tophc7/mix.nix/<commit-sha>";
in
{
  imports = [
    mix-nix.homeManagerModules.theme
    mix-nix.homeManagerModules.monitors
  ];

  theme = {
    enable = true;
    image = ./wallpaper.jpg;
  };
}
```

> **Note:** Requires `--impure` flag when building. For full host management with `lib.mkFlake`, use a flake-based setup instead.

---

## Home Manager Modules

Import modules via `inputs.mix-nix.homeManagerModules.<name>`.

<details>
<summary><strong>theme</strong> - Wallpaper-based theming with Material You colors</summary>

### theme

A centralized theme specification module. Declares theme identity (wallpaper, colors, icons, fonts) and optionally generates color schemes from your wallpaper using matugen.

> **Note:** This module does NOT wire settings to stylix/GTK. Consumers read `theme.*` values and apply them to their preferred theming system.

#### Core Options

| Option           | Type                  | Default  | Description                 |
| ---------------- | --------------------- | -------- | --------------------------- |
| `theme.enable`   | `bool`                | `false`  | Enable theme specification  |
| `theme.image`    | `path`                | required | Path to wallpaper image     |
| `theme.polarity` | `"light"` \| `"dark"` | `"dark"` | Light or dark theme variant |

#### Icon Options

| Option               | Type                  | Default | Description                                          |
| -------------------- | --------------------- | ------- | ---------------------------------------------------- |
| `theme.icon`         | `null` \| `submodule` | `null`  | Icon theme specification                             |
| `theme.icon.package` | `package`             | -       | Icon theme package (e.g., `pkgs.papirus-icon-theme`) |
| `theme.icon.name`    | `string`              | -       | Icon theme name (e.g., `"Papirus"`)                  |

#### Cursor Options

| Option                  | Type                  | Default | Description                |
| ----------------------- | --------------------- | ------- | -------------------------- |
| `theme.pointer`         | `null` \| `submodule` | `null`  | Cursor theme specification |
| `theme.pointer.package` | `package`             | -       | Cursor theme package       |
| `theme.pointer.name`    | `string`              | -       | Cursor theme name          |
| `theme.pointer.size`    | `int`                 | `24`    | Cursor size in pixels      |

#### Font Options

| Option                           | Type                  | Default | Description                   |
| -------------------------------- | --------------------- | ------- | ----------------------------- |
| `theme.fonts`                    | `null` \| `submodule` | `null`  | Font specification            |
| `theme.fonts.serif`              | `{package, name}`     | -       | Serif font configuration      |
| `theme.fonts.sansSerif`          | `{package, name}`     | -       | Sans-serif font configuration |
| `theme.fonts.monospace`          | `{package, name}`     | -       | Monospace font configuration  |
| `theme.fonts.emoji`              | `{package, name}`     | -       | Emoji font configuration      |
| `theme.fonts.sizes.applications` | `int`                 | `12`    | Application font size         |
| `theme.fonts.sizes.desktop`      | `int`                 | `11`    | Desktop element font size     |
| `theme.fonts.sizes.popups`       | `int`                 | `11`    | Popup/notification font size  |
| `theme.fonts.sizes.terminal`     | `int`                 | `12`    | Terminal font size            |

#### Base16 Color Scheme Options

| Option                  | Type                | Default | Description                           |
| ----------------------- | ------------------- | ------- | ------------------------------------- |
| `theme.base16.file`     | `null` \| `path`    | `null`  | Path to pre-made base16 YAML file     |
| `theme.base16.package`  | `null` \| `package` | `null`  | Base16 scheme package                 |
| `theme.base16.generate` | `bool`              | `false` | Generate from wallpaper using matugen |

> Only one of `base16.file`, `base16.package`, or `base16.generate` can be set.

#### Matugen Options

| Option                    | Type                       | Default               | Description                    |
| ------------------------- | -------------------------- | --------------------- | ------------------------------ |
| `theme.matugen.package`   | `package`                  | `inputs.matugen`      | Matugen package                |
| `theme.matugen.scheme`    | `enum`                     | `"scheme-expressive"` | Material You scheme type       |
| `theme.matugen.templates` | `attrsOf {template, path}` | `{}`                  | Custom template configurations |

**Available schemes:** `scheme-content`, `scheme-expressive`, `scheme-fidelity`, `scheme-fruit-salad`, `scheme-monochrome`, `scheme-neutral`, `scheme-rainbow`, `scheme-tonal-spot`, `scheme-vibrant`

#### Control Options

| Option                        | Type   | Default | Description                               |
| ----------------------------- | ------ | ------- | ----------------------------------------- |
| `theme.installGeneratedFiles` | `bool` | `true`  | Install generated files to home directory |

#### Generated Outputs (Read-Only)

| Option                         | Type                | Description                                     |
| ------------------------------ | ------------------- | ----------------------------------------------- |
| `theme.generated.base16Scheme` | `null` \| `path`    | Path to the generated or provided base16 scheme |
| `theme.generated.files`        | `attrsOf path`      | Paths to all generated matugen files            |
| `theme.generated.derivation`   | `null` \| `package` | The matugen output derivation                   |

#### Usage Example

```nix
{ pkgs, config, ... }:
{
  theme = {
    enable = true;
    image = ./wallpapers/mountain.jpg;
    polarity = "dark";

    icon = {
      package = pkgs.papirus-icon-theme;
      name = "Papirus-Dark";
    };

    pointer = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 24;
    };

    # Generate base16 colors from wallpaper
    base16.generate = true;
    matugen.scheme = "scheme-tonal-spot";

    # Custom templates for other apps
    matugen.templates = {
      waybar = {
        template = ./templates/waybar-colors.css;
        path = ".config/waybar/colors.css";
      };
    };
  };

  # Wire to stylix (example)
  stylix.image = config.theme.image;
  stylix.base16Scheme = config.theme.generated.base16Scheme;
}
```

</details>

<details>
<summary><strong>monitors</strong> - Multi-monitor configuration</summary>

### monitors

A monitor specification module for declaring display layouts. Like the theme module, this provides a centralized source of truth - consumers are responsible for reading `monitors` values and applying them to their compositor or display manager.

> **Note:** The `vrr = "on-demand"` option is specific to niri's fullscreen-only VRR mode, but the module itself is compositor-agnostic.

#### Options

| Option                   | Type                    | Default  | Description                                                   |
| ------------------------ | ----------------------- | -------- | ------------------------------------------------------------- |
| `monitors`               | `listOf submodule`      | `[]`     | List of monitor configurations                                |
| `monitors.*.name`        | `string`                | required | Monitor output name (e.g., `"DP-1"`, `"HDMI-A-1"`, `"eDP-1"`) |
| `monitors.*.primary`     | `bool`                  | `false`  | Whether this is the primary monitor                           |
| `monitors.*.width`       | `int`                   | required | Horizontal resolution in pixels                               |
| `monitors.*.height`      | `int`                   | required | Vertical resolution in pixels                                 |
| `monitors.*.refreshRate` | `int` \| `float`        | `60`     | Refresh rate in Hz                                            |
| `monitors.*.x`           | `int`                   | `0`      | X position in combined display layout                         |
| `monitors.*.y`           | `int`                   | `0`      | Y position in combined display layout                         |
| `monitors.*.scale`       | `number`                | `1.0`    | Display scaling factor (1.0 = 100%)                           |
| `monitors.*.transform`   | `int`                   | `0`      | Rotation (see below)                                          |
| `monitors.*.enabled`     | `bool`                  | `true`   | Whether monitor is enabled                                    |
| `monitors.*.hdr`         | `bool`                  | `false`  | Enable HDR                                                    |
| `monitors.*.vrr`         | `bool` \| `"on-demand"` | `false`  | Variable Refresh Rate                                         |

**Transform values:**
- `0` - Normal (landscape)
- `1` - 90 degrees clockwise (portrait right)
- `2` - 180 degrees (landscape flipped)
- `3` - 270 degrees clockwise (portrait left)
- `4-7` - Flipped variants

**VRR values:**
- `true` - Always enabled
- `false` - Disabled
- `"on-demand"` - Enabled only for fullscreen apps (niri)

> **Assertion:** If monitors are defined, exactly one must be marked as `primary = true`.

#### Usage Example

```nix
{
  monitors = [
    {
      name = "DP-1";
      primary = true;
      width = 2560;
      height = 1440;
      refreshRate = 144;
      vrr = true;
    }
    {
      name = "HDMI-A-1";
      width = 1920;
      height = 1080;
      x = 2560;  # Position to the right
      scale = 1.0;
    }
  ];
}
```

</details>

<details>
<summary><strong>fastfetch</strong> - Styled system info display</summary>

### fastfetch

Opinionated fastfetch configuration with weather integration and custom logos.

#### Options

| Option                           | Type               | Default  | Description                                    |
| -------------------------------- | ------------------ | -------- | ---------------------------------------------- |
| `mix.fastfetch.enable`           | `bool`             | `false`  | Enable fastfetch module                        |
| `mix.fastfetch.weather.location` | `string`           | required | City for weather display (e.g., `"London,UK"`) |
| `mix.fastfetch.logo.source`      | `null` \| `path`   | `null`   | Direct path to logo file (highest priority)    |
| `mix.fastfetch.logo.directory`   | `null` \| `path`   | `null`   | Directory containing hostname-based logos      |
| `mix.fastfetch.logo.hostname`    | `null` \| `string` | `null`   | Hostname for directory lookup                  |

**Logo resolution priority:**
1. `logo.source` - Direct path if specified
2. `logo.directory/<hostname>.png` - Hostname-based lookup
3. Bundled fallback `nix.png`

When used with `mix.hosts.mkHost`, `logo.hostname` defaults to `host.hostName` from specialArgs.

#### Usage Example

```nix
{
  mix.fastfetch = {
    enable = true;
    weather.location = "San Francisco,US";

    # Option A: Direct logo
    logo.source = ./my-logo.png;

    # Option B: Directory-based (looks for <hostname>.png)
    # logo.directory = ./logos;
  };
}
```

</details>

<details>
<summary><strong>nautilus</strong> - File manager configuration</summary>

### nautilus

Configure Nautilus/GNOME Files with GTK bookmarks and custom folder icons.

#### Options

| Option                               | Type                   | Default  | Description                          |
| ------------------------------------ | ---------------------- | -------- | ------------------------------------ |
| `programs.nautilus.enable`           | `bool`                 | `false`  | Enable Nautilus configuration        |
| `programs.nautilus.bookmarks`        | `listOf {path, name?}` | `[]`     | Sidebar bookmarks                    |
| `programs.nautilus.bookmarks.*.path` | `string`               | required | Absolute path for the bookmark       |
| `programs.nautilus.bookmarks.*.name` | `null` \| `string`     | `null`   | Display name (uses basename if null) |
| `programs.nautilus.folderIcons`      | `attrsOf string`       | `{}`     | Folder path to icon name mappings    |

#### Usage Example

```nix
{
  programs.nautilus = {
    enable = true;

    bookmarks = [
      { path = "/fast"; name = "Fast Storage"; }
      { path = "/repo"; name = "Repositories"; }
      { path = "/home/user/Documents"; }  # Uses "Documents" as name
    ];

    folderIcons = {
      "/steam" = "folder-steam";
      "/repo" = "folder-git";
      "/home/user/Downloads" = "folder-download";
    };
  };
}
```

</details>

---

## Flake-Parts Modules

Import all modules at once:
```nix
imports = [ inputs.mix-nix.flakeModules.default ];
```

Or import selectively via `imports = [ inputs.mix-nix.flakeModules.<name> ]`.

<details>
<summary><strong>hosts</strong> - Declarative host and user management</summary>

### hosts

The primary integration point. Define users once, reference them across hosts, and automatically generate `nixosConfigurations`.

#### User Options (`mix.users`)

| Option                            | Type                    | Default                       | Description                            |
| --------------------------------- | ----------------------- | ----------------------------- | -------------------------------------- |
| `mix.users`                       | `attrsOf userSpec`      | `{}`                          | User definitions                       |
| `mix.users.<name>.name`           | `string`                | required                      | Username                               |
| `mix.users.<name>.uid`            | `null` \| `int`         | `null`                        | User ID (null for auto)                |
| `mix.users.<name>.group`          | `string`                | `"users"`                     | Primary group                          |
| `mix.users.<name>.shell`          | `package`               | required                      | Default shell                          |
| `mix.users.<name>.extraGroups`    | `listOf string`         | `["wheel", "networkmanager"]` | Additional groups                      |
| `mix.users.<name>.home`           | `null` \| `{directory}` | `null`                        | Home Manager config (null disables HM) |
| `mix.users.<name>.home.directory` | `path`                  | -                             | Path to user's HM config directory     |

#### Host Options (`mix.hosts`)

| Option                         | Type               | Default          | Description                                          |
| ------------------------------ | ------------------ | ---------------- | ---------------------------------------------------- |
| `mix.hosts`                    | `attrsOf hostSpec` | `{}`             | Host definitions                                     |
| `mix.hosts.<name>.enable`      | `bool`             | `true`           | Build this host                                      |
| `mix.hosts.<name>.hostName`    | `string`           | attr name        | Hostname                                             |
| `mix.hosts.<name>.system`      | `enum`             | `"x86_64-linux"` | Architecture (`x86_64-linux`, `aarch64-linux`)       |
| `mix.hosts.<name>.user`        | `string`           | required         | Username from `mix.users`                            |
| `mix.hosts.<name>.isServer`    | `bool`             | `false`          | Server mode (affects autoLogin)                      |
| `mix.hosts.<name>.isMinimal`   | `bool`             | `false`          | Skip user/host HM directories                        |
| `mix.hosts.<name>.desktop`     | `null` \| `string` | `null`           | Desktop environment (null = headless)                |
| `mix.hosts.<name>.autoLogin`   | `bool`             | derived          | Auto-login (default: `!isServer && desktop != null`) |
| `mix.hosts.<name>.specialArgs` | `attrs`            | `{}`             | Extra specialArgs for nixosSystem                    |

#### Core Modules Options

| Option                | Type                    | Default | Description                                     |
| --------------------- | ----------------------- | ------- | ----------------------------------------------- |
| `mix.coreModules`     | `listOf deferredModule` | `[]`    | NixOS modules applied to ALL hosts              |
| `mix.coreHomeModules` | `listOf deferredModule` | `[]`    | HM modules applied to ALL users with HM enabled |

#### Directory Auto-Discovery

| Option             | Type             | Default | Description                                                |
| ------------------ | ---------------- | ------- | ---------------------------------------------------------- |
| `mix.hostsDir`     | `null` \| `path` | `null`  | Auto-discover NixOS configs from `<hostsDir>/<hostname>/`  |
| `mix.hostsHomeDir` | `null` \| `path` | `null`  | Auto-discover HM configs from `<hostsHomeDir>/<hostname>/` |

#### How Module Import Works

**Important:** mix.nix only imports the `default.nix` from each directory path you provide. It does NOT recursively scan or auto-import sibling files.

For example, with this configuration:
```nix
mix = {
  coreModules = [ ./modules/core ];           # Imports ./modules/core/default.nix
  coreHomeModules = [ ./home/core ];          # Imports ./home/core/default.nix
  hostsDir = ./hosts;                          # Imports ./hosts/<hostname>/default.nix
  hostsHomeDir = ./home/hosts;                 # Imports ./home/hosts/<hostname>/default.nix
  users.toph.home.directory = ./home/users/toph;  # Imports ./home/users/toph/default.nix
};
```

**Each `default.nix` controls what gets imported from its directory.** This gives you full control over your module structure.

##### Using `lib.scanPaths` (Optional)

If you want automatic sibling import, use `lib.scanPaths` in your `default.nix`:

```nix
# modules/core/default.nix
{ lib, ... }:
{
  imports = lib.scanPaths ./.;  # Auto-imports all .nix files and directories with default.nix
}
```

`lib.scanPaths` returns paths to:
- All `.nix` files (except `default.nix` itself)
- All directories (Nix will look for their `default.nix`)

##### ⚠️ Pitfall: Non-Module Directories

`lib.scanPaths` includes ALL directories, so directories without a `default.nix` will cause import failures:

```
home/hosts/gojo/
├── default.nix      # Entry point
├── theme.nix        # ✅ Imported as file
├── config/          # ✅ Imported if config/default.nix exists
│   └── default.nix
└── wallpapers/      # ❌ FAILS - no default.nix!
    └── mountain.png
```

**Solutions:**

1. **Keep assets outside scanned directories:**
   ```
   home/hosts/gojo/
   ├── default.nix
   ├── theme.nix
   └── wallpaper.png   # Reference directly: ./wallpaper.png
   ```

2. **Don't use `scanPaths` - import explicitly:**
   ```nix
   # default.nix
   { ... }:
   {
     imports = [
       ./theme.nix
       ./programs.nix
       # Don't import ./wallpapers - it's just assets
     ];
   }
   ```

3. **Use a dedicated assets path referenced in your config:**
   ```nix
   # theme.nix
   { ... }:
   {
     theme.image = ./assets/wallpaper.png;  # Direct path, not imported
   }
   ```

#### Type Extension

| Option             | Type              | Default                    | Description                                 |
| ------------------ | ----------------- | -------------------------- | ------------------------------------------- |
| `mix.userSpecType` | `raw`             | `lib.hosts.types.userSpec` | Custom user type via `lib.hosts.mkUserSpec` |
| `mix.hostSpecType` | `raw`             | `lib.hosts.types.hostSpec` | Custom host type via `lib.hosts.mkHostSpec` |
| `mix.homeManager`  | `null` \| `attrs` | `inputs.home-manager`      | Home Manager input                          |

#### SpecialArgs Available in Modules

When using `mix.hosts`, these are available in your NixOS and Home Manager modules:

- `host` - The full resolved host spec with user data merged in
- `secrets` - Loaded secrets (if using `mix.secrets`)

#### Usage Example

```nix
{
  imports = [ inputs.mix-nix.flakeModules.hosts ];

  mix = {
    coreModules = [ ./modules/core ];
    coreHomeModules = [ ./home/core ];

    hostsDir = ./hosts;
    hostsHomeDir = ./home/hosts;

    users = {
      toph = {
        name = "toph";
        uid = 1000;
        shell = pkgs.fish;
        home.directory = ./home/users/toph;  # Enables HM
      };
      admin = {
        name = "admin";
        shell = pkgs.bash;
        # No home = system user only, no Home Manager
      };
    };

    hosts = {
      desktop = {
        user = "toph";  # References mix.users.toph
        desktop = "niri";
        # autoLogin defaults to true (not server, has desktop)
      };
      server = {
        user = "admin";
        isServer = true;
        system = "aarch64-linux";
        # autoLogin defaults to false (is server)
      };
      laptop = {
        user = "toph";
        desktop = "gnome";
        isMinimal = true;  # Only coreHomeModules, skip user/host dirs
      };
    };
  };
}
```

</details>

<details>
<summary><strong>secrets</strong> - Git-crypt encrypted secrets</summary>

### secrets

Load git-crypt encrypted secrets with validation to prevent accidental plaintext commits.

#### Options

| Option                       | Type               | Default         | Description                                         |
| ---------------------------- | ------------------ | --------------- | --------------------------------------------------- |
| `mix.secrets.file`           | `null` \| `path`   | `null`          | Path to secrets.nix (should be git-crypt encrypted) |
| `mix.secrets.gitattributes`  | `null` \| `path`   | `null`          | Path to .gitattributes for validation               |
| `mix.secrets.pattern`        | `string`           | `"secrets.nix"` | Pattern to match in .gitattributes                  |
| `mix.secrets.skipValidation` | `bool`             | `false`         | Skip git-crypt check (NOT RECOMMENDED)              |
| `mix.secrets.loaded`         | `attrsOf anything` | (read-only)     | The loaded secrets                                  |

#### Usage Example

```nix
{
  imports = [
    inputs.mix-nix.flakeModules.secrets
    inputs.mix-nix.flakeModules.hosts
  ];

  mix.secrets = {
    file = ./secrets.nix;
    gitattributes = ./.gitattributes;
  };

  # Secrets are automatically available in NixOS/HM modules via:
  # - specialArgs: secrets.myKey
  # - Or access config.mix.secrets.loaded.myKey in flake-parts
}
```

Your `.gitattributes` should include:
```
secrets.nix filter=git-crypt diff=git-crypt
```

</details>

<details>
<summary><strong>modules</strong> - NixOS and Home Manager module exports</summary>

### modules

Exposes NixOS and Home Manager modules as flake outputs.

**Outputs:**
- `nixosModules.<name>` - Individual NixOS modules
- `nixosModules.default` - All NixOS modules
- `homeManagerModules.<name>` - Individual HM modules
- `homeManagerModules.default` - All HM modules

```nix
# Import individual module
imports = [ inputs.mix-nix.homeManagerModules.theme ];

# Import all modules
imports = [ inputs.mix-nix.homeManagerModules.default ];
```

</details>

<details>
<summary><strong>overlays</strong> - Package overlays</summary>

### overlays

Provides a combined overlay with stable/unstable channels and custom packages.

**Provides:**
- `pkgs.stable.*` - Packages from stable nixpkgs
- `pkgs.unstable.*` - Packages from unstable nixpkgs
- Custom packages from mix.nix
- Package overrides

```nix
{
  nixpkgs.overlays = [ inputs.mix-nix.overlays.default ];
}

# Then use:
environment.systemPackages = [ pkgs.stable.firefox pkgs.unstable.neovim ];
```

</details>

<details>
<summary><strong>packages</strong> - Custom package definitions</summary>

### packages

Custom packages built by mix.nix.

```bash
# List available packages
nix flake show github:tophc7/mix.nix

# Build a package
nix build github:tophc7/mix.nix#packageName
```

</details>

<details>
<summary><strong>devshell</strong> - Development environment</summary>

### devshell

Development environment for working on mix.nix itself.

**Includes:**
- `nil` - Nix LSP
- `nixfmt-rfc-style` - Official Nix formatter
- `statix` - Nix linter
- `deadnix` - Dead code finder
- `git`

```bash
nix develop  # Enter development shell
nix fmt      # Format with nixfmt-rfc-style
```

</details>

---

## Library Reference

Internal utilities for direct use. Access via the extended `lib`.

### lib.fs - Filesystem Utilities

Directory scanning and module auto-discovery.

- `scanPaths path` - List importable files (directories + .nix, excluding default.nix)
- `scanNames path` - List filenames only (without full paths)
- `importAll path args` - Import all modules, return list
- `importAndMerge path args` - Import and recursively merge attrsets
- `scanModules path args` - Import as named attrset `{name = module; ...}`

### lib.mkFlake - Standalone Flake Builder

For non-flake-parts users. Returns `{ nixosConfigurations = {...}; }`.

```nix
lib.mkFlake {
  inputs;                    # Required: flake inputs
  users;                     # Required: { name = userSpec; }
  hosts;                     # Required: { name = hostSpec; }
  secrets ? {};              # Optional: { file, gitattributes, ... }
  coreModules ? [];          # Optional: NixOS modules for all hosts
  coreHomeModules ? [];      # Optional: HM modules for all users
  hostsDir ? null;           # Optional: auto-discover NixOS configs
  hostsHomeDir ? null;       # Optional: auto-discover HM configs
  homeManager ? null;        # Optional: home-manager input
}
```

### lib.hosts - Host Management

Types and builders for declarative configurations.

- `types.userSpec` - User specification type
- `types.hostSpec` - Host specification type
- `mkUserSpec extraModule` - Factory to extend user type
- `mkHostSpec extraModule` - Factory to extend host type
- `mkHost {...}` - Build single nixosConfiguration
- `mkHosts {...}` - Build multiple nixosConfigurations

### lib.desktop - Desktop Utilities

- `mkWineApp pkgs {...}` - Create Wine application wrapper with isolated prefix
- `matugen.mkBase16Template {...}` - Generate base16 template for matugen
- `matugen.mkTemplateConfig {...}` - Generate matugen template config
- `matugen.mkDerivation {...}` - Build matugen derivation
- `monitors.findPrimary monitors` - Find primary monitor
- `monitors.filterEnabled monitors` - Filter enabled monitors
- `monitors.totalWidth monitors` - Calculate total width
- `monitors.totalHeight monitors` - Calculate max height
- 
### lib.secrets - Secrets Management

- `load {path, gitattributes, ...}` - Import secrets with git-crypt validation
- `mkModule secrets` - Generate NixOS/HM module exposing secrets
- `assertGitCrypt {gitattributesPath, pattern}` - Validate git-crypt config

---

## Real-World Example

Complete flake.nix showing typical usage:

```nix
{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";

    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mix-nix = {
      url = "github:tophc7/mix.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, mix-nix, ... }:
    flake-parts.lib.mkFlake {
      inherit inputs;
      specialArgs = { lib = mix-nix.lib; };
    } ({ pkgs, ... }: {
      imports = [ mix-nix.flakeModules.default ];

      systems = [ "x86_64-linux" "aarch64-linux" ];

      mix = {
        # Secrets (git-crypt encrypted)
        secrets = {
          file = ./secrets.nix;
          gitattributes = ./.gitattributes;
        };

        # Core modules for all hosts
        coreModules = [
          ./modules/core
          ./modules/nix-settings.nix
        ];
        coreHomeModules = [
          ./home/core
          mix-nix.homeManagerModules.theme
          mix-nix.homeManagerModules.monitors
        ];

        # Auto-discovery directories
        hostsDir = ./hosts;
        hostsHomeDir = ./home/hosts;

        # User definitions
        users.toph = {
          name = "toph";
          uid = 1000;
          shell = pkgs.fish;
          extraGroups = [ "wheel" "docker" "audio" "video" ];
          home.directory = ./home/users/toph;
        };

        # Host definitions
        hosts = {
          desktop = {
            user = "toph";
            desktop = "niri";
          };
          laptop = {
            user = "toph";
            desktop = "gnome";
          };
          homelab = {
            user = "toph";
            isServer = true;
          };
        };
      };
    });
}
```

**Directory structure recommendation:**
```
.
├── flake.nix
├── secrets.nix         # git-crypt encrypted
├── .gitattributes      # secrets.nix filter=git-crypt
├── modules/
│   ├── core/           # Essential NixOS modules (applied to all)
│   │   ├── home/       # Core HM modules
│   │   └── host/       # Core NixOS modules
│   └── common/         # Optional shared modules
│       ├── home/
│       └── host/
├── hosts/
│   ├── desktop/        # Auto-imported for 'desktop' host
│   ├── laptop/
│   └── homelab/
└── home/
    ├── users/
    │   └── toph/       # User-specific HM config
    └── hosts/
        ├── desktop/    # Host-specific HM config
        ├── laptop/
        └── homelab/
```

---

## Design Philosophy

1. **Directory Auto-Discovery Over Explicit Lists**
   Drop files in directories - they're automatically imported. No manual `imports = [ ./a.nix ./b.nix ]`.

2. **Declarative Specs Describe "What", Not "How"**
   Specifications define properties and identity. Implementation details live in directories.

3. **Convention Over Configuration**
   Consistent directory structures reduce cognitive load. Follow established patterns.

4. **Extensibility Via Factory Functions**
   Base types stay minimal. Use `mkUserSpec`/`mkHostSpec` to add custom options.

5. **Tools Over Configs**
   While some modules (like fastfetch) include opinionated defaults, the focus is on providing reusable tools and specifications rather than full system configurations.

---

## Contributing

### Development Setup

```bash
# Enter development shell
nix develop

# Available tools: nil, nixfmt-rfc-style, statix, deadnix, git
```

### Commands

```bash
# Check flake validity
nix flake check

# Format code
nix fmt

# Show outputs
nix flake show
```

### Guidelines

- Follow existing code patterns
- Add documentation in file headers
- Use `nixfmt-rfc-style` formatting
- Test changes with `nix flake check`
