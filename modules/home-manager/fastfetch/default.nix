# Opinionated fastfetch configuration
#
# A fastfetch module with styled system info display.
# Configures programs.fastfetch with curated settings.
#
# Usage:
#   imports = [ inputs.mix-nix.homeManagerModules.fastfetch ];
#
#   mix.fastfetch = {
#     enable = true;
#     weather.location = "London,UK";
#
#     # Option A: Direct logo path
#     logo.source = ./my-logo.png;
#
#     # Option B: Directory-based (looks for hostname.png)
#     logo.directory = ./logos;
#   };
#
# Auto-discovery (when used with mix.hosts):
#   If no logo options are set, looks for logo.png in the user's
#   home.directory (from host.user.home.directory).
#   e.g., ./home/gojo/logo.png
#
{
  lib,
  pkgs,
  config,
  host ? null, # From specialArgs when used with mkHost
  ...
}:
let
  cfg = config.mix.fastfetch;

  # Import scripts
  weather = import ./scripts/weather.nix { inherit pkgs lib; };
  title = import ./scripts/title.nix { inherit pkgs; };

  # Bundled fallback logo
  fallbackLogo = ./assets/nix.png;

  # Resolve hostname for directory-based lookup
  # Priority: explicit option > host.hostName from specialArgs
  resolvedHostname =
    if cfg.logo.hostname != null then
      cfg.logo.hostname
    else if host != null && host ? hostName then
      host.hostName
    else
      null;

  # Get user's home directory from host spec (if available)
  userHomeDir =
    if host != null && host ? user && host.user ? home && host.user.home != null then
      host.user.home.directory
    else
      null;

  # Resolve logo file
  # Priority: source > directory lookup > user home directory > fallback
  logoFile =
    if cfg.logo.source != null then
      cfg.logo.source
    else if cfg.logo.directory != null && resolvedHostname != null then
      let
        hostLogoPath = cfg.logo.directory + "/${resolvedHostname}.png";
      in
      if builtins.pathExists hostLogoPath then hostLogoPath else fallbackLogo
    else if userHomeDir != null then
      # Auto-discover from user's home.directory
      let
        homeLogoPath = userHomeDir + "/logo.png";
      in
      if builtins.pathExists homeLogoPath then homeLogoPath else fallbackLogo
    else
      fallbackLogo;

in
{
  options.mix.fastfetch = {
    enable = lib.mkEnableOption "fastfetch with opinionated rice config";

    weather = {
      location = lib.mkOption {
        type = lib.types.str;
        description = "City name for weather display (e.g., 'London' or 'Richmond,US')";
        example = "London,UK";
      };
    };

    logo = {
      source = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Direct path to logo file (takes priority over directory lookup)";
        example = "./my-logo.png";
      };

      directory = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Directory containing hostname-based logos.
          Looks for <hostname>.png in this directory.
          Falls back to bundled nix.png if not found.
        '';
        example = "./logos";
      };

      hostname = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Hostname for directory-based lookup.
          Defaults to host.hostName when used with mix.hosts.mkHost.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    programs.fastfetch = {
      enable = true;
      settings = {
        logo = {
          type = "kitty";
          source = logoFile;
          width = 26;
          height = 15;
          padding = {
            top = 1;
            right = 2;
            left = 2;
          };
        };

        display = {
          bar = {
            border.left = "⦉";
            border.right = "⦊";
            char.elapsed = "⏹";
            charTotal = "⬝";
            width = 10;
          };
          percent = {
            type = 2;
          };
          separator = "";
        };

        modules = [
          "break"
          {
            key = " ";
            shell = "fish";
            text = "fish ${title}";
            type = "command";
          }
          "break"
          {
            key = "weather » {#keys}";
            keyColor = "1;97";
            shell = "${lib.getExe pkgs.fish}";
            text = "fish ${weather} '${cfg.weather.location}'";
            type = "command";
          }
          {
            key = "cpu     » {#keys}";
            keyColor = "1;31";
            showPeCoreCount = true;
            type = "cpu";
          }
          {
            format = "{0} {2}";
            key = "gpu     » {#keys}";
            keyColor = "1;93";
            type = "gpu";
            hideType = "integrated";
          }
          {
            format = "{0} ({#3;32}{3}{#})";
            key = "wm      » {#keys}";
            keyColor = "1;32";
            type = "wm";
          }
          {
            text =
              let
                name = lib.getName pkgs.fish;
              in
              "printf '%s%s' (string upper (string sub -l 1 ${name})) (string lower (string sub -s 2 ${name}))";
            key = "shell   » {#keys}";
            keyColor = "1;33";
            type = "command";
            shell = "${lib.getExe pkgs.fish}";
          }
          {
            key = "uptime  » {#keys}";
            keyColor = "1;34";
            type = "uptime";
          }
          {
            folders = "/";
            format = "{0~0,-4} / {2} {13}";
            key = "disk    » {#keys}";
            keyColor = "1;35";
            type = "disk";
          }
          {
            format = "{0~0,-4} / {2} {4}";
            key = "memory  » {#keys}";
            keyColor = "1;36";
            type = "memory";
          }
          {
            format = "{ipv4~0,-3} ({#3;32}{ifname}{#})";
            key = "network » {#keys}";
            keyColor = "1;37";
            type = "localip";
          }
          {
            format = "{2} ({#3;32}{4}{#})";
            key = "kernel  » {#keys}";
            keyColor = "1;94";
            type = "kernel";
          }
          {
            key = "media   » {#keys}";
            keyColor = "5;92";
            type = "command";
            shell = "${lib.getExe pkgs.fish}";
            text = "${lib.getExe pkgs.playerctl} metadata --format '{{ artist }} - {{ title }} ('(set_color green)'{{ playerName }}'(set_color normal)')' 2>/dev/null; or echo 'No media playing'";
          }
          "break"
          {
            symbol = "square";
            type = "colors";
          }
          "break"
        ];
      };
    };
  };
}
