# mix.nix <picture><source srcset="https://fonts.gstatic.com/s/e/notoemoji/latest/2744_fe0f/512.webp" type="image/webp"><img src="https://fonts.gstatic.com/s/e/notoemoji/latest/2744_fe0f/512.gif" alt="❄" width="32" height="32" align="top"></picture>

> **A convention-driven NixOS and Home Manager framework for multi-host flakes.**
>
> [![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/TophC7/mix.nix)

**mix.nix follows a folder layout to create NixOS hosts.** You declare users and hosts in a few lines of Nix. Everything else is decided by *where a file lives*: which config belongs to which host, which Home Manager config belongs to which user, and how a feature splits between NixOS and Home Manager.

That is the idea behind mix, and it's why this README starts with the layout. Once you understand the paths below, nothing mix.nix does should surprise you. For a real configuration built this way, see my own at [tophc7/dot.nix](https://github.com/tophc7/dot.nix).

mix.nix also ships standalone modules (wallpaper theming, monitors, Pangolin tunnels, OCI stacks) and a `lib` of helpers. Those work without the host framework.

> This describes configuration **API v2** (`mix.apiVersion = 2`). The default, deprecated v1 is covered under [API versions](#api-versions).

## The layout

```
flake.nix                      imports mix-nix.flakeModules.default and ./mix
mix/default.nix                mix = { apiVersion = 2; users = …; hosts = …; }
hosts/
├── desktop/
│   ├── default.nix            NixOS for host "desktop"
│   ├── hardware.nix           anything else is yours to import
│   └── home/default.nix       Home Manager for desktop's user   (or home.nix)
└── homelab.nix                a single-file host: NixOS only
modules/
├── core/
│   ├── default.nix            NixOS for every host              (or modules/core.nix)
│   └── home/default.nix       Home Manager shared on every host (or home.nix)
├── users/
│   └── toph/default.nix       toph's Home Manager profile       (or toph.nix)
└── features/
    └── gaming/
        ├── nixos.nix          NixOS half
        └── home.nix           Home Manager half
```

| Path | Used when | Goes into |
| --- | --- | --- |
| `hosts/<host>/` or `hosts/<host>.nix` | `<host>` is declared in `mix.hosts` | that host's NixOS config |
| `hosts/<host>/home/` or `home.nix` | the host is a directory and its user is enrolled | the enrolled user's Home Manager, after the profile |
| `modules/core/` or `modules/core.nix` | always | every host's NixOS config |
| `modules/core/home/` or `home.nix` | core is a directory and Home Manager is available | `home-manager.sharedModules` on every host |
| `modules/users/<user>/` or `<user>.nix` | a host uses `<user>` | enrolls the user as `home-manager.users.<user>` |
| `modules/features/<name>/` | a NixOS module calls `lib.features [ "<name>" ]` | `nixos.nix` → NixOS, `home.nix` → `home-manager.sharedModules` |

A few rules follow from the table:

- **Paths are fixed.** They are relative to your flake root (`inputs.self`), and there are no options to move them. The one folder mix.nix does not read is `mix/`: it's where your `mix = { … }` config conventionally lives, and `flake.nix` imports it.
- **Nothing is required.** A missing path just means nothing is found: a host without `hosts/<host>` still gets core, and a user without a profile gets no Home Manager.
- **A folder means its `default.nix`.** Hosts, user profiles and core may also be a single `<name>.nix` file where a folder would be ceremony; if both exist, the folder wins. Only folders can hold a `home` part.
- **mix.nix imports entrypoints, not trees.** It imports `default.nix` (or the single file); whatever else that file imports is up to you.

## What happens when a host is built

For `mix.hosts.desktop = { user = "toph"; }`:

```
nixosConfigurations.desktop
├── NixOS
│   ├── modules/core                      every host
│   ├── hosts/desktop                     this host
│   │   └── lib.features [ "gaming" ]  →  modules/features/gaming/nixos.nix
│   └── from mix.nix: hostname, users.users.toph, secrets, mix.nix's overlay
└── Home Manager (when the home-manager input exists)
    ├── sharedModules: modules/core/home, modules/features/gaming/home.nix
    └── users.toph (only if modules/users/toph exists)
        ├── secrets module
        ├── modules/users/toph
        └── hosts/desktop/home
```

Home Manager has two separate switches:

- **Integration** loads on every host whenever `mix.homeManager` is set (it defaults to `inputs.home-manager`), so core and features can always contribute shared modules.
- **Enrollment** creates `home-manager.users.<user>` only when that user's profile exists. An empty `{ }` profile is enough to enroll with just the shared modules.

### Module arguments

Every NixOS and Home Manager module of a mix.nix host receives:

- `host`: the host's spec, with `host.user` resolved to the full user spec (plus `homeDirectory`; in Home Manager, `shell` is resolved to a package)
- `hosts`: every host spec, for cross-host lookups such as VPN peers
- `inputs`: your flake inputs, merged over mix.nix's own
- `secrets`: values loaded through [`mix.secrets`](#secrets) (empty when unused)
- anything in `mix.specialArgs` or `mix.hosts.<host>.specialArgs`

`lib` is mix.nix's extended lib (`lib.fs`, `lib.desktop`, …). In NixOS modules of v2 hosts it also has [`lib.features`](#libfeatures---feature-directories).

```nix
# hosts/desktop/default.nix
{ host, lib, ... }:
{
  imports = [ ./hardware.nix ] ++ lib.features [ "gaming" ];
  users.users.${host.user.name}.extraGroups = [ "gamemode" ];
}
```

## Quick start

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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

  outputs =
    inputs@{ flake-parts, mix-nix, ... }:
    flake-parts.lib.mkFlake
      {
        inherit inputs;
        specialArgs = { lib = mix-nix.lib; };
      }
      {
        imports = [
          mix-nix.flakeModules.default
          ./mix
        ];
        systems = [ "x86_64-linux" ];
      };
}
```

```nix
# mix/default.nix
{
  mix = {
    apiVersion = 2;

    users.toph = {
      name = "toph";
      shell = "fish";
    };

    hosts = {
      desktop.user = "toph";
      homelab = {
        user = "toph";
        isServer = true;
      };
    };
  };
}
```

Add `hosts/desktop/default.nix` (with its hardware config) and `modules/users/toph/default.nix`, and `nixosConfigurations.desktop` is ready to build. Without flake-parts, [`lib.mkFlake`](#libmkflake---standalone-flake-builder) takes the same `users`/`hosts` and returns `nixosConfigurations`.

## Features

A feature is a folder that can carry both halves of one capability: `nixos.nix` for the system (packages, services, udev rules) and `home.nix` for the user (dotfiles, app settings). Either half is optional.

```
modules/features/gaming/
├── nixos.nix     Steam, GameMode
└── home.nix      MangoHud, launcher settings
```

Nothing under `modules/features` loads on its own. A NixOS module opts in by name:

```nix
{ lib, ... }:
{
  imports = lib.features [ "gaming" "pangolin/newt" ./local-feature ];
}
```

`nixos.nix` is imported into NixOS, and `home.nix` is added to `home-manager.sharedModules` by path, so Home Manager evaluates it in its own context. On a flake without Home Manager (`mix.homeManager = null`), `home.nix` is ignored, like every other Home Manager part. Names may be nested (`"pangolin/newt"`), and a path loads a feature folder from anywhere.

## Worth knowing

- **NixOS and Home Manager are separate evaluations.** A folder that mixes them (a host folder, a core folder, a feature) must never be imported wholesale. `lib.fs.scanPaths ./.` in `hosts/desktop/default.nix` would feed `home/` to NixOS, which usually fails with *"The option `home' does not exist"*. `scanPaths` warns when the folder it scans contains `home/` or `home.nix`. Scan single-context subfolders instead, such as `lib.fs.scanPaths ./config`.
- **Host Home Manager belongs to the host's user.** `hosts/<host>/home` is imported only for `host.user`, and only if that user is enrolled.
- **Profiles are personal; core and features are shared.** `modules/users/<user>` applies to that user alone. Anything several users or hosts need belongs in `modules/core` or a feature.

## Building on another flake

A second flake, such as installer ISOs, can reuse an existing layout instead of copying it:

```nix
# iso/mix/default.nix
{ dotRoot, ... }:
{
  mix = {
    apiVersion = 2;
    extends = dotRoot;   # e.g. ../. passed in through specialArgs
    hostSpecExtensions = [ (dotRoot + "/mix/hostSpec.nix") ];
    # users, hosts, secrets …
  };
}
```

- Hosts, user profiles and features are looked up in this flake first, then in the extended one.
- The extended flake's `modules/core` applies first, then this flake's own `modules/core`, so the ISO can add its installer settings on top.
- It is one level deep: the extended flake's own `extends` is not followed.
- `hostSpecExtensions` and `secrets` are not inherited; set them where you need them.

[tophc7/dot.nix](https://github.com/tophc7/dot.nix)'s `dist/` builds its ISOs this way.

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
<summary><strong>hosts</strong> - Users, hosts and the <code>mix.*</code> options</summary>

### hosts

Declares users and hosts and generates `nixosConfigurations` from them, following [the layout](#the-layout).

#### User Options (`mix.users`)

| Option                         | Type                  | Default                       | Description                                   |
| ------------------------------ | --------------------- | ----------------------------- | --------------------------------------------- |
| `mix.users`                    | `attrsOf userSpec`    | `{}`                          | User definitions                              |
| `mix.users.<name>.name`        | `string`              | required                      | Username                                      |
| `mix.users.<name>.uid`         | `null` \| `int`       | `null`                        | User ID (null for auto)                       |
| `mix.users.<name>.group`       | `string`              | `"users"`                     | Primary group                                 |
| `mix.users.<name>.shell`       | `package` \| `string` | required                      | Default shell (package or name like `"fish"`) |
| `mix.users.<name>.extraGroups` | `listOf string`       | `["wheel", "networkmanager"]` | Additional groups                             |

#### Host Options (`mix.hosts`)

| Option                         | Type               | Default          | Description                                    |
| ------------------------------ | ------------------ | ---------------- | ---------------------------------------------- |
| `mix.hosts`                    | `attrsOf hostSpec` | `{}`             | Host definitions                               |
| `mix.hosts.<name>.enable`      | `bool`             | `true`           | Build this host                                |
| `mix.hosts.<name>.hostName`    | `string`           | attr name        | Hostname                                       |
| `mix.hosts.<name>.system`      | `enum`             | `"x86_64-linux"` | Architecture (`x86_64-linux`, `aarch64-linux`) |
| `mix.hosts.<name>.user`        | `string`           | required         | Username from `mix.users`                      |
| `mix.hosts.<name>.isServer`    | `bool`             | `false`          | Server flag, readable as `host.isServer`       |
| `mix.hosts.<name>.isMinimal`   | `bool`             | `false`          | **v1 only**: HM user gets only secrets + `coreHomeModules`. v2 has no such flag: setting it is an error unless you declare your own with `mix.hostSpecExtensions` |
| `mix.hosts.<name>.specialArgs` | `attrs`            | `{}`             | Extra specialArgs for this host                |

#### Other Options

| Option                   | Type                    | Default                | Description |
| ------------------------ | ----------------------- | ---------------------- | ----------- |
| `mix.apiVersion`         | `int` (1 or 2)          | `1`                    | Configuration API; see [API versions](#api-versions) |
| `mix.extends`            | `null` \| `path`         | `null`                 | v2 only: layout root to fall back to; see [Building on another flake](#building-on-another-flake) |
| `mix.hostSpecExtensions` | `listOf deferredModule` | `[]`                   | Modules adding options to every host spec |
| `mix.userSpecExtensions` | `listOf deferredModule` | `[]`                   | Modules adding options to every user spec |
| `mix.homeManager`        | `null` \| `attrs`        | `inputs.home-manager`  | Home Manager input; `null` disables Home Manager (profiles, host/core `home`, and feature `home.nix` are all ignored) |
| `mix.specialArgs`        | `attrs`                 | `{}`                   | Extra arguments for every host's NixOS and Home Manager modules |

#### Extending host and user specs

Extensions add your own fields to every host or user, readable in modules as `host.<field>`:

```nix
mix.hostSpecExtensions = [
  ({ lib, ... }: {
    options.desktop = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "gnome" "niri" ]);
      default = null;
    };
  })
];

mix.hosts.desktop = {
  user = "toph";
  desktop = "niri";
};
```

For a larger example, see `mix/hostSpec.nix` in [tophc7/dot.nix](https://github.com/tophc7/dot.nix).

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
| `eden-bin`             | Eden from the official prebuilt AppImage (no compile) |
| `eightbitdo-updater`   | 8BitDo controller firmware updater                    |
| `gamescope-git`        | Gamescope compositor (git version)                    |
| `gamescope-git.wsi`    | Gamescope WSI layer only (git version)                |
| `helium`               | Chromium-based private web browser                    |
| `journey`              | Cross-platform journal app                            |
| `monocraft-nerd-fonts` | Minecraft-style monospace font with Nerd Font icons   |
| `olm-toggle`           | GNOME Shell extension to toggle OLM tunneling service |
| `switch2-controllers`  | Wireless Nintendo Switch 2 controller bridge          |
| `proton-cachyos`       | CachyOS Proton build (baseline x86-64)                |
| `proton-cachyos.v3`    | CachyOS Proton build (x86-64-v3, AVX2)                |
| `WiiUDownloader`       | GUI to download Wii U content from Nintendo servers   |

```bash
# List available packages
nix flake show github:tophc7/mix.nix

# Build a package
nix build github:tophc7/mix.nix#proton-cachyos
```

#### CachyOS Kernel Variants

Optimized kernel configurations for different workloads:

| Package | Use Case | Key Settings |
|---------|----------|--------------|
| `linuxPackages-ryot` | Desktop/Gaming | 1000Hz, ThinLTO, full preemption |
| `linuxPackages-ryot-zfs` | ZFS Servers | 500Hz, ThinLTO, includes `zfs_cachyos` |
| `linuxPackages-ryot-net` | Routers | 300Hz, no LTO, voluntary preemption |

```nix
# Desktop/Gaming
boot.kernelPackages = pkgs.linuxPackages-ryot;

# ZFS Server (use zfs_cachyos for compatibility)
boot.kernelPackages = pkgs.linuxPackages-ryot-zfs;
boot.zfs.package = config.boot.kernelPackages.zfs_cachyos;

# Router
boot.kernelPackages = pkgs.linuxPackages-ryot-net;
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

- `scanPaths path` - Returns paths to all importable modules (directories + .nix, excluding `default.nix` and `_*`); warns when `path` contains `home/` or `home.nix` (see [Worth knowing](#worth-knowing)). If that `home` entry is meant to be scanned, list imports explicitly instead, or prefix it with `_` to keep it out of the scan
- `scanNames path` - Returns just filenames (not full paths)
- `scanAttrs path` - Returns attrset of `{ name = ./path; }` for module indices
- `importAndMerge path args` - Import all files and merge their attrsets
- `importAttrs path args` - Import all and return attrset of evaluated results
- `relativeTo basePath` - Curried path resolver for composability with map

### lib.mkFlake - Standalone Flake Builder

For non-flake-parts users. Returns `{ nixosConfigurations = {...}; }` and follows [the layout](#the-layout) under `inputs.self`.

```nix
lib.mkFlake {
  inputs;                    # Required: flake inputs (including self)
  users;                     # Required: { name = userSpec; }
  hosts;                     # Required: { name = hostSpec; }
  apiVersion ? 1;            # Set 2 for the layout described here
  extends ? null;            # v2: layout root to fall back to
  secrets ? {};              # Optional: { file, gitattributes, ... }
  homeManager ? inputs.home-manager or null;
  # v1 only: coreModules, coreHomeModules, hostsDir, hostsHomeDir, usersHomeDir
}
```

### lib.features - Feature Directories

Available as `lib.features` in NixOS modules of v2 hosts; see [Features](#features).

- String entries name a folder under `modules/features` (local flake first, then `mix.extends`); names may nest (`"pangolin/newt"`).
- Path entries (or absolute strings) load that folder directly.
- Each folder must hold `nixos.nix`, `home.nix`, or both; otherwise evaluation fails naming the folder.

### lib.hosts - Host Management

Types and builders for declarative configurations.

- `types.userSpec` - User specification type (default, no extensions)
- `types.hostSpec` - Host specification type (default, no extensions)
- `modules.baseUserSpec` - Base user module (for submoduleWith imports)
- `modules.baseHostSpec` - Base host module (for submoduleWith imports)
- `mkUserSpecType [modules]` - Build userSpec type with extension modules
- `mkHostSpecType [modules]` - Build hostSpec type with extension modules (API v1 shape, including `isMinimal`, like `types.hostSpec`)
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

#### Builders

- `mkWailsApp pkgs {...}` - Create native desktop apps using Wails v2 (webkit2gtk, native Wayland)
  - Supports two modes: `url` (connect to external service) or `command` (spawn + wrap CLI)
  - Produces a native Go binary with hicolor icons and .desktop entry
  - **URL Mode Example** (connect to self-hosted service):
    ```nix
    lib.desktop.mkWailsApp pkgs {
      pname = "myapp-desktop";
      desktopName = "My App";
      programName = "myapp-desktop";
      icon = ./icon.png;
      url.default = "http://localhost:6369";
    }
    ```
  - **Command Mode Example** (CLI wrapper with auto-port):
    ```nix
    lib.desktop.mkWailsApp pkgs {
      pname = "myapp-desktop";
      desktopName = "My App";
      programName = "myapp-desktop";
      icon = ./icon.png;
      command = {
        package = pkgs.myapp-cli;
        binName = "myapp";
        args = [ "serve" "--port" "{port}" "--host" "{host}" ];
        defaultPort = 8080;
      };
      monoFont = {                        # Optional: override monospace font
        package = monocraft-nerd-fonts;
        name = "Monocraft Nerd Font";
      };
    }
    ```
  - Common parameters: `pname`, `desktopName`, `programName`, `icon`, `window` (width/height), `title`, `version`, `categories`, `monoFont`

- `mkWineApp pkgs {...}` - Create Wine application wrapper with isolated prefix

#### Color & Theme

- `matugen.mkBase16Template {...}` - Generate base16 template for matugen
- `matugen.mkTemplateConfig {...}` - Generate matugen template config
- `matugen.mkDerivation {...}` - Build matugen derivation

#### Monitor Utilities

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

## API versions

Omitting `mix.apiVersion` selects **v1**. It keeps existing flakes working unchanged, and every evaluation warns once that it is deprecated. A future release will make omitted/1 an error; it will never silently switch to v2.

- **v1 (deprecated):** locations are options (`hostsDir`, `hostsHomeDir`, `usersHomeDir`, `coreModules`, `coreHomeModules`); Home Manager loads only for users with a profile; `isMinimal` trims a host's Home Manager to secrets + `coreHomeModules`. No `lib.features`; `extends` is rejected.
- **v2:** the fixed [layout](#the-layout). The v1 location options are rejected with an error, even when set to `[]` or `null`.

### Migrating from v1

| v1 | v2 |
| --- | --- |
| `apiVersion` omitted | `mix.apiVersion = 2;` |
| `hostsDir = ./hosts;` | Remove. Host configs live at `hosts/<host>/` or `hosts/<host>.nix` in the flake root. |
| `hostsHomeDir = ./home/hosts;` | Remove. Move `home/hosts/<host>/` to `hosts/<host>/home/`; a single-file host must become `hosts/<host>/default.nix` first. |
| `usersHomeDir = ./home/users;` | Remove. Move profiles to `modules/users/<user>/` (or `<user>.nix`). |
| `coreModules = [ ./modules/core … ];` | Remove. `modules/core/` (or `modules/core.nix`) is imported on every host; import any other always-on modules from it. |
| `coreHomeModules = [ ./home/core ];` | Remove. Move it to `modules/core/home/` (or `modules/core/home.nix`). |
| `home-manager.sharedModules = [ ./home ]` next to a NixOS module | Make it a feature, `modules/features/<name>/{nixos.nix,home.nix}`, and load it with `lib.features [ "<name>" ]`. |
| `isMinimal = true` trimming Home Manager | v2 has no `isMinimal`; setting it without declaring it is an error. If you want the flag, add it with `mix.hostSpecExtensions` and gate with `lib.mkIf (!host.isMinimal)` where it matters. |
| Another flake's paths in `coreModules` | `mix.extends = <that flake's root>;` |

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
