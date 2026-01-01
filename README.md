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
- [NixOS Modules](#nixos-modules)
  - [newt](#newt)
  - [olm](#olm)
  - [oci-stacks](#oci-stacks)
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

## NixOS Modules

Import modules via `inputs.mix-nix.nixosModules.<name>`.

<details>
<summary><strong>newt</strong> - Pangolin Docker tunnel client</summary>

### newt

Runs Newt in a Docker container for Pangolin tunneling with full Docker socket access, enabling container network validation and orchestration features.

> **Note:** This module disables the upstream native `services.networking.newt` module to avoid conflicts. Use upstream if you prefer a native (non-Docker) approach.

#### Options

| Option                           | Type               | Default        | Description                                       |
| -------------------------------- | ------------------ | -------------- | ------------------------------------------------- |
| `services.newt.enable`           | `bool`             | `false`        | Enable Newt Docker container service              |
| `services.newt.id`               | `string`           | required       | Newt ID for authentication with Pangolin server   |
| `services.newt.secret`           | `null` \| `string` | `null`         | Plaintext secret (not recommended for production) |
| `services.newt.secretFile`       | `null` \| `path`   | `null`         | Path to env file containing `NEWT_SECRET=...`     |
| `services.newt.image`            | `string`           | `"fosrl/newt"` | Docker image to use                               |
| `services.newt.pangolinEndpoint` | `string`           | required       | Pangolin server endpoint URL                      |
| `services.newt.networkName`      | `string`           | `"newt"`       | Docker network name for container communication   |
| `services.newt.networkAlias`     | `string`           | `"newt"`       | Network alias for the container                   |
| `services.newt.useHostNetwork`   | `bool`             | `false`        | Use host networking (disables network validation) |
| `services.newt.extraNetworks`    | `listOf string`    | `[]`           | Additional Docker networks to connect to          |

> **Authentication:** Either `secret` or `secretFile` must be set, but not both. Use `secretFile` with sops-nix or agenix for production.

#### Usage Example

```nix
{ config, ... }:
{
  imports = [ inputs.mix-nix.nixosModules.newt ];

  services.newt = {
    enable = true;
    id = "your-newt-id";
    secretFile = config.sops.secrets.newt-secret.path;
    pangolinEndpoint = "https://pangolin.example.com";

    # Optional: connect to additional networks
    extraNetworks = [ "traefik" ];
  };
}
```

</details>

<details>
<summary><strong>olm</strong> - Pangolin native tunnel client</summary>

### olm

Native OLM binary for WireGuard-based Pangolin tunneling. Connects your machine directly to Pangolin/Newt sites without Docker.

#### Core Options

| Option                    | Type               | Default  | Description                                |
| ------------------------- | ------------------ | -------- | ------------------------------------------ |
| `services.olm.enable`     | `bool`             | `false`  | Enable OLM tunneling client                |
| `services.olm.autoStart`  | `bool`             | `false`  | Start automatically at boot                |
| `services.olm.id`         | `string`           | required | OLM client identifier                      |
| `services.olm.secret`     | `null` \| `string` | `null`   | Plaintext secret (not recommended)         |
| `services.olm.secretFile` | `null` \| `path`   | `null`   | Path to file containing the secret         |
| `services.olm.endpoint`   | `string`           | required | Pangolin endpoint URL                      |
| `services.olm.configFile` | `null` \| `path`   | `null`   | Config file path (overrides other options) |

#### Network Options

| Option                       | Type               | Default  | Description                              |
| ---------------------------- | ------------------ | -------- | ---------------------------------------- |
| `services.olm.endpointIP`    | `null` \| `string` | `null`   | Direct IP to bypass DNS/proxy            |
| `services.olm.mtu`           | `int`              | `1280`   | Network interface MTU                    |
| `services.olm.dns`           | `null` \| `string` | `null`   | DNS server (uses system default if null) |
| `services.olm.interfaceName` | `string`           | `"olm0"` | WireGuard interface name                 |
| `services.olm.holepunch`     | `bool`             | `false`  | Enable NAT traversal (experimental)      |

#### Connection Options

| Option                      | Type             | Default  | Description                         |
| --------------------------- | ---------------- | -------- | ----------------------------------- |
| `services.olm.logLevel`     | `enum`           | `"INFO"` | DEBUG, INFO, WARN, ERROR, or FATAL  |
| `services.olm.pingInterval` | `string`         | `"3s"`   | Server ping frequency               |
| `services.olm.pingTimeout`  | `string`         | `"5s"`   | Ping response timeout               |
| `services.olm.healthFile`   | `null` \| `path` | `null`   | Path for connection status tracking |

#### Desktop Integration

| Option                               | Type      | Default           | Description                     |
| ------------------------------------ | --------- | ----------------- | ------------------------------- |
| `services.olm.package`               | `package` | `pkgs.fosrl-olm`  | OLM package to use              |
| `services.olm.enableGnomeExtension`  | `bool`    | `false`           | Enable GNOME Shell panel toggle |
| `services.olm.gnomeExtensionPackage` | `package` | `pkgs.olm-toggle` | GNOME extension package         |

> **Authentication:** One of `secret`, `secretFile`, or `configFile` must be set. Use `secretFile` with sops-nix or agenix for production.

#### Usage Example

```nix
{ config, ... }:
{
  imports = [ inputs.mix-nix.nixosModules.olm ];

  services.olm = {
    enable = true;
    autoStart = false;  # Manual control via systemctl
    id = "your-olm-id";
    secretFile = config.sops.secrets.olm-secret.path;
    endpoint = "https://pangolin.example.com";

    # Optional tuning
    mtu = 1400;
    logLevel = "DEBUG";

    # Desktop integration
    enableGnomeExtension = true;
  };
}
```

</details>

<details>
<summary><strong>oci-stacks</strong> - OCI container stack orchestration</summary>

### oci-stacks

Abstracts Docker container orchestration boilerplate by generating network services, systemd service configuration, and root targets from simple stack definitions.

> **Note:** Modules using `lib.infra.*` require the extended lib via `specialArgs` in `nixosSystem`.

#### Options

| Option | Type | Default | Description |
| ------ | ---- | ------- | ----------- |
| `virtualisation.oci-stacks` | `attrsOf stackType` | `{}` | OCI container stack definitions |
| `virtualisation.oci-stacks.<name>.containers` | `attrsOf attrs` | `{}` | Container definitions (passed to `oci-containers`) |
| `virtualisation.oci-stacks.<name>.network` | `string` \| `submodule` | stack name | Network configuration |
| `virtualisation.oci-stacks.<name>.description` | `null` \| `string` | `null` | Description for the systemd root target |

#### Network Options

When `network` is an attrset instead of a string:

| Option | Type | Default | Description |
| ------ | ---- | ------- | ----------- |
| `network.name` | `null` \| `string` | stack name | Network name |
| `network.driver` | `string` | `"bridge"` | Docker network driver |
| `network.subnet` | `null` \| `string` | `null` | Network subnet (e.g., `"10.1.1.0/24"`) |
| `network.gateway` | `null` \| `string` | `null` | Network gateway IP |
| `network.script` | `null` \| `lines` | `null` | Custom network creation script |
| `network.external` | `listOf string` | `[]` | External networks (soft dependencies from other stacks) |

#### What It Generates

For each stack, the module automatically creates:
- **Containers** passed through to `virtualisation.oci-containers`
- **Network service** (`docker-network-<name>`) with automatic creation/cleanup
- **Container services** with restart policies via `lib.infra.containers.serviceDefaults`
- **Network dependencies** wired between containers and networks
- **Root systemd target** (`docker-compose-<name>-root`) for orchestration

#### Usage Example

```nix
{ config, ... }:
{
  imports = [ inputs.mix-nix.nixosModules.oci-stacks ];

  virtualisation.oci-stacks.myapp = {
    containers.myapp = {
      image = "myapp:latest";
      ports = [ "8080:80" ];
      extraOptions = [
        "--network=myapp"
        "--network-alias=myapp"
      ];
    };
    description = "My application stack";
  };

  # With custom network configuration
  virtualisation.oci-stacks.database = {
    containers.postgres = {
      image = "postgres:16";
      extraOptions = [
        "--network=database"
        "--network-alias=db"
      ];
      environment = {
        POSTGRES_PASSWORD = "secret";
      };
    };
    network = {
      name = "database";
      subnet = "10.1.1.0/24";
      gateway = "10.1.1.1";
    };
  };

  # Stack depending on external network
  virtualisation.oci-stacks.webapp = {
    containers.web = {
      image = "nginx:latest";
      extraOptions = [
        "--network=webapp"
        "--network=database"  # Connect to database network
      ];
    };
    network = {
      external = [ "database" ];  # Soft dependency on database network
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

| Option                         | Type                  | Default                       | Description                                   |
| ------------------------------ | --------------------- | ----------------------------- | --------------------------------------------- |
| `mix.users`                    | `attrsOf userSpec`    | `{}`                          | User definitions                              |
| `mix.users.<name>.name`        | `string`              | required                      | Username                                      |
| `mix.users.<name>.uid`         | `null` \| `int`       | `null`                        | User ID (null for auto)                       |
| `mix.users.<name>.group`       | `string`              | `"users"`                     | Primary group                                 |
| `mix.users.<name>.shell`       | `package` \| `string` | required                      | Default shell (package or name like `"fish"`) |
| `mix.users.<name>.extraGroups` | `listOf string`       | `["wheel", "networkmanager"]` | Additional groups                             |

> **Note:** Home Manager is auto-enabled via `usersHomeDir` discovery. If `<usersHomeDir>/<username>/` or `<usersHomeDir>/<username>.nix` exists, HM is enabled for that user.

#### Host Options (`mix.hosts`)

| Option                         | Type               | Default          | Description                                    |
| ------------------------------ | ------------------ | ---------------- | ---------------------------------------------- |
| `mix.hosts`                    | `attrsOf hostSpec` | `{}`             | Host definitions                               |
| `mix.hosts.<name>.enable`      | `bool`             | `true`           | Build this host                                |
| `mix.hosts.<name>.hostName`    | `string`           | attr name        | Hostname                                       |
| `mix.hosts.<name>.system`      | `enum`             | `"x86_64-linux"` | Architecture (`x86_64-linux`, `aarch64-linux`) |
| `mix.hosts.<name>.user`        | `string`           | required         | Username from `mix.users`                      |
| `mix.hosts.<name>.isServer`    | `bool`             | `false`          | Server mode (affects extension defaults)       |
| `mix.hosts.<name>.isMinimal`   | `bool`             | `false`          | Skip user/host HM directories                  |
| `mix.hosts.<name>.specialArgs` | `attrs`            | `{}`             | Extra specialArgs for nixosSystem              |

> **Desktop Configuration:** For desktop environment and greeter options (DE type, auto-login, etc.), use the [arroz.nix](https://github.com/toph/arroz.nix) extension which adds these via `mix.hostSpecExtensions`.

#### Core Modules Options

| Option                | Type                    | Default | Description                                     |
| --------------------- | ----------------------- | ------- | ----------------------------------------------- |
| `mix.coreModules`     | `listOf deferredModule` | `[]`    | NixOS modules applied to ALL hosts              |
| `mix.coreHomeModules` | `listOf deferredModule` | `[]`    | HM modules applied to ALL users with HM enabled |

#### Directory Auto-Discovery

| Option             | Type             | Default | Description                                                 |
| ------------------ | ---------------- | ------- | ----------------------------------------------------------- |
| `mix.hostsDir`     | `null` \| `path` | `null`  | Auto-discover NixOS configs from `<hostsDir>/<hostname>/`   |
| `mix.hostsHomeDir` | `null` \| `path` | `null`  | Auto-discover HM configs from `<hostsHomeDir>/<hostname>/`  |
| `mix.usersHomeDir` | `null` \| `path` | `null`  | Auto-discover user HM configs from `<usersHomeDir>/<user>/` |

> **Note:** Home Manager is automatically enabled for a user when their home config path exists (either via `usersHomeDir` auto-discovery or explicit `home.directory`).

#### Flat File Support

Auto-discovery supports **both directory and flat file** layouts:

```
# Directory style (recommended for complex configs)
hosts/desktop/default.nix     →  imported as ./hosts/desktop
home/users/toph/default.nix   →  imported as ./home/users/toph

# Flat file style (simpler for small configs)
hosts/desktop.nix             →  imported directly
home/users/toph.nix           →  imported directly
```

The lookup order is: directory first, then flat file.

#### How Module Import Works

**Important:** mix.nix only imports the `default.nix` from each directory path you provide. It does NOT recursively scan or auto-import sibling files.

For example, with this configuration:
```nix
mix = {
  coreModules = [ ./modules/core ];    # Imports ./modules/core/default.nix
  coreHomeModules = [ ./home/core ];   # Imports ./home/core/default.nix
  hostsDir = ./hosts;                  # Imports ./hosts/<hostname>/ or ./hosts/<hostname>.nix
  hostsHomeDir = ./home/hosts;         # Imports ./home/hosts/<hostname>/ or .nix
  usersHomeDir = ./home/users;         # Imports ./home/users/<username>/ or .nix (enables HM)
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
- **Excludes** entries starting with `_` (e.g., `_helpers.nix`, `_internal/`)

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

#### Type Extensions

Extend the host and user specification types by adding modules to the extension lists. This allows multiple flakes (e.g., arroz.nix, play.nix) to compose additional options without conflicts.

| Option                   | Type                    | Default | Description                                   |
| ------------------------ | ----------------------- | ------- | --------------------------------------------- |
| `mix.hostSpecExtensions` | `listOf deferredModule` | `[]`    | Modules to add options to hostSpec type       |
| `mix.userSpecExtensions` | `listOf deferredModule` | `[]`    | Modules to add options to userSpec type       |
| `mix.homeManager`        | `null` \| `attrs`       | `inputs.home-manager` | Home Manager input              |

**Extension Example (from arroz.nix):**
```nix
# arroz.nix/parts/hosts.nix
{ config, ... }: {
  config.mix.hostSpecExtensions = [
    ({ lib, ... }: {
      options.desktop.niri.enable = lib.mkEnableOption "Niri compositor";
      options.greeter.type = lib.mkOption {
        type = lib.types.str;
        default = "tuigreet";
      };
    })
  ];
}
```

Then consumers can use these extended options:
```nix
mix.hosts.desktop = {
  user = "toph";
  desktop.niri.enable = true;  # From arroz.nix extension
  greeter.type = "regreet";    # From arroz.nix extension
};
```

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

    # Auto-discover user HM configs from ./home/users/<username>/
    usersHomeDir = ./home/users;

    users = {
      toph = {
        name = "toph";
        uid = 1000;
        shell = pkgs.fish;
        # HM enabled via usersHomeDir auto-discovery (./home/users/toph/)
      };
      admin = {
        name = "admin";
        shell = pkgs.bash;
        # No ./home/users/admin/ = system user only, no Home Manager
      };
    };

    hosts = {
      desktop = {
        user = "toph";  # References mix.users.toph
      };
      server = {
        user = "admin";
        isServer = true;
        system = "aarch64-linux";
      };
      laptop = {
        user = "toph";
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

| Package                | Description                                           |
| ---------------------- | ----------------------------------------------------- |
| `eden`                 | Nintendo Switch video game console emulator           |
| `eightbitdo-updater`   | 8BitDo controller firmware updater                    |
| `journey`              | Cross-platform journal app                            |
| `monocraft-nerd-fonts` | Minecraft-style monospace font with Nerd Font icons   |
| `olm-toggle`           | GNOME Shell extension to toggle OLM tunneling service |
| `procon2-init`         | Nintendo Switch 2 Pro Controller USB initializer      |
| `proton-cachyos`       | CachyOS Proton build with optimizations               |
| `WiiUDownloader`       | GUI to download Wii U content from Nintendo servers   |

```bash
# List available packages
nix flake show github:tophc7/mix.nix

# Build a package
nix build github:tophc7/mix.nix#proton-cachyos
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

**Convention:** Files and directories starting with `_` are excluded from all scan/import functions. Use this for private helpers or internal modules (e.g., `_helpers.nix`, `_internal/`).

- `scanPaths path` - Returns paths to all importable modules (directories + .nix, excluding `default.nix` and `_*`)
- `scanNames path` - Returns just filenames (not full paths)
- `scanAttrs path` - Returns attrset of `{ name = ./path; }` for module indices
- `importAndMerge path args` - Import all files and merge their attrsets
- `importAttrs path args` - Import all and return attrset of evaluated results
- `relativeTo basePath` - Curried path resolver for composability with map

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
  hostsHomeDir ? null;       # Optional: auto-discover host HM configs
  usersHomeDir ? null;       # Optional: auto-discover user HM configs
  homeManager ? null;        # Optional: home-manager input
}
```

### lib.hosts - Host Management

Types and builders for declarative configurations.

- `types.userSpec` - User specification type (default, no extensions)
- `types.hostSpec` - Host specification type (default, no extensions)
- `modules.baseUserSpec` - Base user module (for submoduleWith imports)
- `modules.baseHostSpec` - Base host module (for submoduleWith imports)
- `mkUserSpecType [modules]` - Build userSpec type with extension modules
- `mkHostSpecType [modules]` - Build hostSpec type with extension modules
- `mkHost {...}` - Build single nixosConfiguration
- `mkHosts {...}` - Build multiple nixosConfigurations

> **Note:** The `shell` option in userSpec accepts either a `package` or a `string` (e.g., `pkgs.fish` or `"fish"`).

### lib.infra.containers - Docker Container Utilities

Utilities for OCI container management with systemd integration.

- `serviceDefaults` - Default systemd service config for containers (restart policies, timing)

For full container stack orchestration (networks, targets, dependencies), use the [`oci-stacks` module](#oci-stacks) instead.

#### Usage Example

```nix
{ lib, ... }:
{
  # Apply service defaults to a container service
  systemd.services."docker-myapp".serviceConfig = lib.infra.containers.serviceDefaults;
}
```

### lib.desktop - Desktop Utilities

- `mkWineApp pkgs {...}` - Create Wine application wrapper with isolated prefix
- `matugen.mkBase16Template {...}` - Generate base16 template for matugen
- `matugen.mkTemplateConfig {...}` - Generate matugen template config
- `matugen.mkDerivation {...}` - Build matugen derivation
- `monitors.findPrimary monitors` - Find primary monitor from list
- `monitors.findByName name monitors` - Find monitor by output name (e.g., "DP-1")
- `monitors.filterEnabled monitors` - Filter to only enabled monitors
- `monitors.countPrimary monitors` - Count monitors marked as primary (for validation)
- `monitors.getDefaults monitors` - Get primary monitor settings with fallbacks `{ width, height, refreshRate, vrr, hdr }`
- `monitors.effectiveWidth monitor` - Get width accounting for rotation
- `monitors.effectiveHeight monitor` - Get height accounting for rotation
- `monitors.isPortrait monitor` - Check if rotated 90/270 degrees
- `monitors.toResolutionStr monitor` - Format as "WIDTHxHEIGHT@RATE"
- `monitors.toPositionStr monitor` - Format position as "Xx Y"
- `monitors.totalWidth monitors` - Calculate total width of enabled monitors (scaled)
- `monitors.totalHeight monitors` - Calculate max height of enabled monitors (scaled)

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
        usersHomeDir = ./home/users;  # HM enabled if ./home/users/<username>/ exists

        # User definitions
        users.toph = {
          name = "toph";
          uid = 1000;
          shell = pkgs.fish;
          extraGroups = [ "wheel" "docker" "audio" "video" ];
          # HM auto-enabled via usersHomeDir (./home/users/toph/)
        };

        # Host definitions
        hosts = {
          desktop = {
            user = "toph";
          };
          laptop = {
            user = "toph";
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


**Directory structure (directories - complex configs):**
```
.
├── flake.nix
├── secrets.nix               # git-crypt encrypted
├── .gitattributes            # secrets.nix filter=git-crypt
├── modules/
│   ├── home/
│   │   ├── core/
│   │   │   └── default.nix   # Core HM modules (applied to all)
│   │   └── common/
│   │       └── default.nix   # Optional shared HM modules
│   └── host/
│       ├── core/
│       │   └── default.nix   # Core NixOS modules (applied to all)
│       └── common/
│           └── default.nix   # Optional shared NixOS modules
├── hosts/
│   ├── desktop/
│   │   └── default.nix       # NixOS config for 'desktop' host
│   ├── laptop/
│   │   └── default.nix
│   └── homelab/
│       └── default.nix
└── home/
    ├── users/
    │   └── toph/
    │       └── default.nix   # User-specific HM config (enables HM)
    └── hosts/
        ├── desktop/
        │   └── default.nix   # Host-specific HM config
        ├── laptop/
        │   └── default.nix
        └── homelab/
            └── default.nix
```

**Directory structure (flat files - simpler):**
```
.
├── flake.nix
├── secrets.nix           # git-crypt encrypted
├── home/
│   ├── core.nix          # Core HM modules
│   ├── hosts/
│   │   ├── desktop.nix   # Host-specific HM config
│   │   └── server.nix
│   └── users/
│       └── toph.nix      # User-specific HM config (enables HM)
├── hosts/
│   ├── desktop.nix       # NixOS config for desktop
│   └── server.nix        # NixOS config for server
└── modules/
    ├── core.nix          # Core NixOS modules
    └── secrets.nix       # git-crypt encrypted
```

---

## Design Philosophy

1. **Directory Auto-Discovery Over Explicit Lists**
   Drop files in directories - they're automatically imported. No manual `imports = [ ./a.nix ./b.nix ]`.

2. **Declarative Specs Describe "What", Not "How"**
   Specifications define properties and identity. Implementation details live in directories.

3. **Convention Over Configuration**
   Consistent directory structures reduce cognitive load. Follow established patterns.

4. **Extensibility Via Composable Extensions**
   Base types stay minimal. Use `mix.hostSpecExtensions`/`mix.userSpecExtensions` to add custom options from multiple flakes.

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
