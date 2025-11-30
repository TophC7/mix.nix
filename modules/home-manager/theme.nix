# Theme specification module for desktop environments
#
# This module provides a centralized source of truth for theme settings.
# It declares theme identity (wallpaper, colors, icons, fonts) and optionally
# generates color schemes from wallpaper using matugen.
#
# The module does NOT wire settings to stylix/GTK - consumers are responsible
# for reading theme.* values and applying them to their preferred theming system.
#
# Usage:
#   imports = [ inputs.mix-nix.homeManagerModules.theme ];
#
#   theme = {
#     enable = true;
#     image = ./wallpaper.jpg;
#     polarity = "dark";
#     icon = { package = pkgs.papirus-icon-theme; name = "Papirus"; };
#     base16.generate = true;
#   };
#
#   # Consumer wires to stylix:
#   stylix.image = config.theme.image;
#   stylix.base16Scheme.yaml = config.theme.generated.base16Scheme;
#
{ lib, config, pkgs, inputs, ... }:

let
  cfg = config.theme;

  # Import matugen lib functions
  matugenLib = (import ../../lib/desktop/matugen.nix { inherit lib; }).matugen;

  # Font submodule type
  fontType = lib.types.submodule {
    options = {
      package = lib.mkOption {
        type = lib.types.package;
        description = "The font package";
        example = lib.literalExpression "pkgs.lexend";
      };
      name = lib.mkOption {
        type = lib.types.str;
        description = "The font name";
        example = "Lexend";
      };
    };
  };

  # Build base16 template file
  base16TemplateFile = pkgs.writeText "matugen-base16-template.yaml" (
    matugenLib.mkBase16Template { inherit (cfg) polarity; }
  );

  # Build all matugen templates including base16 if generate is enabled
  allMatugenTemplates =
    cfg.matugen.templates
    // lib.optionalAttrs cfg.base16.generate {
      __base16 = {
        template = base16TemplateFile;
        path = ".local/share/base16/matugen-scheme.yaml";
      };
    };

  # Check if we need to run matugen at all
  needsMatugen =
    cfg.enable && ((lib.length (lib.attrNames cfg.matugen.templates) > 0) || cfg.base16.generate);

  # Build the matugen derivation
  matugenGenerated =
    if needsMatugen then
      matugenLib.mkDerivation {
        inherit pkgs;
        matugenPackage = cfg.matugen.package;
        image = cfg.image;
        polarity = cfg.polarity;
        scheme = cfg.matugen.scheme;
        templates = allMatugenTemplates;
      }
    else
      null;

in
{
  options.theme = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable theme specification";
    };

    # Core identity (REQUIRED)
    image = lib.mkOption {
      type = lib.types.path;
      description = "Path to the wallpaper image";
      example = lib.literalExpression "./wallpapers/landscape.jpg";
    };

    polarity = lib.mkOption {
      type = lib.types.enum [ "light" "dark" ];
      default = "dark";
      description = "Whether to use light or dark theme variant";
    };

    # Icon specification (OPTIONAL)
    icon = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          package = lib.mkOption {
            type = lib.types.package;
            description = "The icon theme package";
            example = lib.literalExpression "pkgs.papirus-icon-theme";
          };
          name = lib.mkOption {
            type = lib.types.str;
            description = "The icon theme name";
            example = "Papirus";
          };
        };
      });
      default = null;
      description = "Icon theme specification (null to leave unset)";
    };

    # Cursor specification (OPTIONAL)
    pointer = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          package = lib.mkOption {
            type = lib.types.package;
            description = "The cursor theme package";
            example = lib.literalExpression "pkgs.bibata-cursors";
          };
          name = lib.mkOption {
            type = lib.types.str;
            description = "The cursor theme name";
            example = "Bibata-Modern-Classic";
          };
          size = lib.mkOption {
            type = lib.types.int;
            default = 24;
            description = "The cursor size in pixels";
          };
        };
      });
      default = null;
      description = "Cursor theme specification (null to leave unset)";
    };

    # Font specification (OPTIONAL)
    fonts = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          serif = lib.mkOption {
            type = fontType;
            description = "Serif font configuration";
          };
          sansSerif = lib.mkOption {
            type = fontType;
            description = "Sans-serif font configuration";
          };
          monospace = lib.mkOption {
            type = fontType;
            description = "Monospace font configuration";
          };
          emoji = lib.mkOption {
            type = fontType;
            description = "Emoji font configuration";
          };
          sizes = lib.mkOption {
            type = lib.types.submodule {
              options = {
                applications = lib.mkOption {
                  type = lib.types.int;
                  default = 12;
                  description = "Font size for applications";
                };
                desktop = lib.mkOption {
                  type = lib.types.int;
                  default = 11;
                  description = "Font size for desktop elements";
                };
                popups = lib.mkOption {
                  type = lib.types.int;
                  default = 11;
                  description = "Font size for popups and notifications";
                };
                terminal = lib.mkOption {
                  type = lib.types.int;
                  default = 12;
                  description = "Font size for terminal emulators";
                };
              };
            };
            default = { };
            description = "Font sizes for different contexts";
          };
        };
      });
      default = null;
      description = "Font specification (null to leave unset)";
    };

    # Base16 color scheme options
    base16 = {
      file = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to a pre-made base16 YAML color scheme file";
        example = lib.literalExpression "./colors.yaml";
      };

      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = "A base16 scheme package (e.g., pkgs.base16-schemes)";
        example = lib.literalExpression "pkgs.base16-schemes";
      };

      generate = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Generate base16 scheme from wallpaper using matugen.
          When true, automatically generates a base16-compatible color scheme.
        '';
      };
    };

    # Matugen configuration
    matugen = {
      package = lib.mkOption {
        type = lib.types.package;
        default = inputs.matugen.packages.${pkgs.stdenv.hostPlatform.system}.default;
        defaultText = lib.literalExpression "inputs.matugen.packages.\${system}.default";
        description = "The matugen package to use for color generation";
      };

      scheme = lib.mkOption {
        type = lib.types.enum [
          "scheme-content"
          "scheme-expressive"
          "scheme-fidelity"
          "scheme-fruit-salad"
          "scheme-monochrome"
          "scheme-neutral"
          "scheme-rainbow"
          "scheme-tonal-spot"
          "scheme-vibrant"
        ];
        default = "scheme-expressive";
        description = "Material You scheme type for color generation";
        example = "scheme-tonal-spot";
      };

      templates = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            template = lib.mkOption {
              type = lib.types.path;
              description = "Path to the matugen template file";
              example = lib.literalExpression "./templates/style.css";
            };
            path = lib.mkOption {
              type = lib.types.str;
              description = "Output path for the generated file (relative to HOME)";
              example = ".config/myapp/colors.css";
            };
          };
        });
        default = { };
        description = ''
          Matugen template configurations.
          Each template will be processed with colors from the wallpaper.
        '';
        example = lib.literalExpression ''
          {
            waybar = {
              template = ./templates/waybar.css;
              path = ".config/waybar/colors.css";
            };
          }
        '';
      };
    };

    # Control behavior
    installGeneratedFiles = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install generated matugen files to home directory";
    };

    # Read-only generated outputs
    generated = {
      base16Scheme = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        readOnly = true;
        description = "Path to the generated or provided base16 scheme";
      };

      files = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = { };
        readOnly = true;
        description = "Paths to all generated matugen files";
      };

      derivation = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        readOnly = true;
        description = "The matugen output derivation (if any)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      let
        base16Options = [
          (cfg.base16.file != null)
          (cfg.base16.package != null)
          cfg.base16.generate
        ];
        base16OptionsSet = lib.count lib.id base16Options;
      in
      [
        {
          assertion = cfg.image != null;
          message = "theme.image must be set when theme is enabled";
        }
        {
          assertion = base16OptionsSet <= 1;
          message = ''
            theme.base16.file, theme.base16.package, and theme.base16.generate are mutually exclusive.
            Only one can be set at a time.
          '';
        }
      ];

    # Set generated outputs
    theme.generated = {
      base16Scheme =
        if cfg.base16.file != null then
          cfg.base16.file
        else if cfg.base16.package != null then
          cfg.base16.package
        else if cfg.base16.generate && matugenGenerated != null then
          "${matugenGenerated}/.local/share/base16/matugen-scheme.yaml"
        else
          null;

      files =
        if matugenGenerated != null then
          lib.mapAttrs' (_: tmpl: {
            name = tmpl.path;
            value = "${matugenGenerated}/${tmpl.path}";
          }) allMatugenTemplates
        else
          { };

      derivation = matugenGenerated;
    };

    # Install generated matugen files to home directory
    home.file = lib.mkIf (cfg.installGeneratedFiles && matugenGenerated != null) (
      lib.mapAttrs' (_: tmpl: {
        name = tmpl.path;
        value = {
          source = "${matugenGenerated}/${tmpl.path}";
        };
      }) allMatugenTemplates
    );
  };
}
