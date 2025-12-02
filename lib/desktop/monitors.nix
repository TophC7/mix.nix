# Monitor utility functions for display configuration
#
# Provides reusable patterns for working with monitor specifications
# including resolution handling, layout calculations, and primary detection.
#
# Usage:
#   lib.desktop.monitors.findPrimary config.monitors
#   lib.desktop.monitors.toResolutionStr monitor
#   lib.desktop.monitors.getDefaults config.monitors
#
{ lib }:

{
  monitors = {
    # Count monitors marked as primary (for validation)
    #
    # Arguments:
    #   monitors: List of monitor attrsets with `primary` boolean
    #
    # Returns: Integer count of primary monitors
    #
    # Usage:
    #   lib.desktop.monitors.countPrimary config.monitors
    #
    countPrimary = monitors: lib.length (lib.filter (m: m.primary) monitors);

    # Get effective height accounting for rotation
    #
    # Arguments:
    #   monitor: Monitor attrset with `width`, `height`, and `transform`
    #
    # Returns: Integer height (swapped with width if rotated 90/270 degrees)
    #
    # Usage:
    #   lib.desktop.monitors.effectiveHeight monitor
    #
    effectiveHeight =
      monitor:
      if (monitor.transform == 1 || monitor.transform == 3) then monitor.width else monitor.height;

    # Get effective width accounting for rotation
    #
    # Arguments:
    #   monitor: Monitor attrset with `width`, `height`, and `transform`
    #
    # Returns: Integer width (swapped with height if rotated 90/270 degrees)
    #
    # Usage:
    #   lib.desktop.monitors.effectiveWidth monitor
    #
    effectiveWidth =
      monitor:
      if (monitor.transform == 1 || monitor.transform == 3) then monitor.height else monitor.width;

    # Get all enabled monitors from a list
    #
    # Arguments:
    #   monitors: List of monitor attrsets with `enabled` boolean
    #
    # Returns: Filtered list containing only enabled monitors
    #
    # Usage:
    #   lib.desktop.monitors.filterEnabled config.monitors
    #
    filterEnabled = monitors: lib.filter (m: m.enabled) monitors;

    # Find a monitor by its name
    #
    # Arguments:
    #   name: String identifier to search for (e.g., "DP-1", "HDMI-A-1")
    #   monitors: List of monitor attrsets with `name` attribute
    #
    # Returns: Monitor attrset if found, null otherwise
    #
    # Usage:
    #   lib.desktop.monitors.findByName "DP-1" config.monitors
    #
    findByName = name: monitors: lib.findFirst (m: m.name == name) null monitors;

    # Find the primary monitor from a list
    #
    # Arguments:
    #   monitors: List of monitor attrsets with `primary` boolean
    #
    # Returns: Monitor attrset if primary found, null otherwise
    #
    # Usage:
    #   lib.desktop.monitors.findPrimary config.monitors
    #
    findPrimary = monitors: lib.findFirst (m: m.primary) null monitors;

    # Get default display values from primary monitor
    #
    # Extracts common display settings from the primary monitor with
    # sensible fallbacks when no primary is defined.
    #
    # Arguments:
    #   monitors: List of monitor attrsets
    #
    # Returns: Attrset { width, height, refreshRate, vrr, hdr }
    #
    # Usage:
    #   lib.desktop.monitors.getDefaults config.monitors
    #
    getDefaults =
      monitors:
      let
        primary = lib.findFirst (m: m.primary) null monitors;
        toInt = v: if builtins.isInt v then v else builtins.ceil v;
      in
      {
        width = if primary != null then primary.width else 1920;
        height = if primary != null then primary.height else 1080;
        refreshRate = if primary != null then toInt primary.refreshRate else 60;
        vrr = if primary != null then primary.vrr else false;
        hdr = if primary != null then primary.hdr else false;
      };

    # Check if monitor is in portrait mode
    #
    # Arguments:
    #   monitor: Monitor attrset with `transform` attribute
    #
    # Returns: Boolean true if rotated 90 or 270 degrees (transform 1 or 3)
    #
    # Usage:
    #   lib.desktop.monitors.isPortrait monitor
    #
    isPortrait = monitor: monitor.transform == 1 || monitor.transform == 3;

    # Format monitor position as string
    #
    # Arguments:
    #   monitor: Monitor attrset with `x` and `y` coordinates
    #
    # Returns: String in format "Xx Y" (e.g., "1920x0")
    #
    # Usage:
    #   lib.desktop.monitors.toPositionStr monitor
    #
    toPositionStr = monitor: "${toString monitor.x}x${toString monitor.y}";

    # Format monitor resolution and refresh rate as string
    #
    # Arguments:
    #   monitor: Monitor attrset with `width`, `height`, and `refreshRate`
    #
    # Returns: String in format "WIDTHxHEIGHT@RATE" (e.g., "1920x1080@144")
    #
    # Usage:
    #   lib.desktop.monitors.toResolutionStr monitor
    #
    toResolutionStr =
      monitor: "${toString monitor.width}x${toString monitor.height}@${toString monitor.refreshRate}";

    # Calculate maximum height among all enabled monitors (scaled)
    #
    # Arguments:
    #   monitors: List of monitor attrsets with `enabled`, `height`, and `scale`
    #
    # Returns: Integer representing max scaled height across enabled monitors
    #
    # Usage:
    #   lib.desktop.monitors.totalHeight config.monitors
    #
    totalHeight =
      monitors:
      lib.foldl' (
        acc: m: lib.max acc (if m.enabled then builtins.ceil (m.height / m.scale) else 0)
      ) 0 monitors;

    # Calculate total width of all enabled monitors (scaled)
    #
    # Arguments:
    #   monitors: List of monitor attrsets with `enabled`, `width`, and `scale`
    #
    # Returns: Integer sum of scaled widths for enabled monitors
    #
    # Usage:
    #   lib.desktop.monitors.totalWidth config.monitors
    #
    totalWidth =
      monitors:
      lib.foldl' (acc: m: acc + (if m.enabled then builtins.ceil (m.width / m.scale) else 0)) 0 monitors;
  };
}
