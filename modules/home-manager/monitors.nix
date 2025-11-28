# Monitor configuration module for desktop environments
#
# Usage:
#   imports = [ inputs.mix-nix.homeManagerModules.monitors ];
#
#   monitors = [
#     {
#       name = "DP-1";
#       primary = true;
#       width = 1920;
#       height = 1080;
#       refreshRate = 144;
#     }
#   ];
#
{ lib, config, ... }:
{
  options.monitors = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Monitor output name (e.g., DP-1, HDMI-A-1, eDP-1)";
            example = "DP-1";
          };

          primary = lib.mkOption {
            type = lib.types.bool;
            description = "Whether this is the primary monitor";
            default = false;
          };

          width = lib.mkOption {
            type = lib.types.int;
            description = "Horizontal resolution in pixels";
            example = 1920;
          };

          height = lib.mkOption {
            type = lib.types.int;
            description = "Vertical resolution in pixels";
            example = 1080;
          };

          refreshRate = lib.mkOption {
            type = lib.types.either lib.types.int lib.types.float;
            description = "Refresh rate in Hz";
            default = 60;
            example = 144;
          };

          x = lib.mkOption {
            type = lib.types.int;
            description = "X position in the combined display layout";
            default = 0;
          };

          y = lib.mkOption {
            type = lib.types.int;
            description = "Y position in the combined display layout";
            default = 0;
          };

          scale = lib.mkOption {
            type = lib.types.number;
            description = "Display scaling factor (1.0 = 100%)";
            default = 1.0;
            example = 1.5;
          };

          transform = lib.mkOption {
            type = lib.types.int;
            description = ''
              Display rotation/transform:
                0 = normal (landscape)
                1 = 90 degrees clockwise (portrait right)
                2 = 180 degrees (landscape flipped)
                3 = 270 degrees clockwise (portrait left)
                4 = flipped
                5 = flipped + 90 degrees
                6 = flipped + 180 degrees
                7 = flipped + 270 degrees
            '';
            default = 0;
          };

          enabled = lib.mkOption {
            type = lib.types.bool;
            description = "Whether the monitor is enabled";
            default = true;
          };

          hdr = lib.mkOption {
            type = lib.types.bool;
            description = "Enable HDR (High Dynamic Range)";
            default = false;
          };

          vrr = lib.mkOption {
            type = lib.types.either lib.types.bool (lib.types.enum [ "on-demand" ]);
            description = ''
              Variable Refresh Rate (VRR) / Adaptive Sync / FreeSync.
              - true: always enabled
              - false: disabled
              - "on-demand": enabled only for fullscreen apps (Niri)
            '';
            default = false;
          };
        };
      }
    );
    default = [ ];
    description = "List of monitor configurations for desktop environments";
  };

  config = {
    assertions = [
      {
        assertion =
          (lib.length config.monitors == 0) || (lib.length (lib.filter (m: m.primary) config.monitors) == 1);
        message = "Exactly one monitor must be set as primary when monitors are defined.";
      }
    ];
  };
}
