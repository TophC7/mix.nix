# Monitor utility functions
#
# Usage:
#   lib.desktop.monitors.findPrimary config.monitors
#   lib.desktop.monitors.toResolutionStr monitor
#
{ lib }:
{
  monitors = {
    # Find the primary monitor from a list
    # Returns null if no primary is set
    findPrimary = monitors: lib.findFirst (m: m.primary) null monitors;

    # Get all enabled monitors
    filterEnabled = monitors: lib.filter (m: m.enabled) monitors;

    # Count primary monitors (for validation)
    countPrimary = monitors: lib.length (lib.filter (m: m.primary) monitors);

    # Calculate total width of all enabled monitors (scaled)
    totalWidth =
      monitors:
      lib.foldl' (acc: m: acc + (if m.enabled then builtins.ceil (m.width / m.scale) else 0)) 0 monitors;

    # Calculate max height among all enabled monitors (scaled)
    totalHeight =
      monitors:
      lib.foldl' (
        acc: m: lib.max acc (if m.enabled then builtins.ceil (m.height / m.scale) else 0)
      ) 0 monitors;

    # Get monitor by name
    findByName = name: monitors: lib.findFirst (m: m.name == name) null monitors;

    # Get resolution string (e.g., "1920x1080@144")
    toResolutionStr =
      monitor: "${toString monitor.width}x${toString monitor.height}@${toString monitor.refreshRate}";

    # Get position string (e.g., "1920x0")
    toPositionStr = monitor: "${toString monitor.x}x${toString monitor.y}";

    # Check if monitor is in portrait mode (90 or 270 degree rotation)
    isPortrait = monitor: monitor.transform == 1 || monitor.transform == 3;

    # Get effective dimensions (accounting for rotation)
    effectiveWidth =
      monitor:
      if (monitor.transform == 1 || monitor.transform == 3) then monitor.height else monitor.width;

    effectiveHeight =
      monitor:
      if (monitor.transform == 1 || monitor.transform == 3) then monitor.width else monitor.height;

    # Get default values from primary monitor
    # Returns { width, height, refreshRate, vrr, hdr } or fallback defaults
    # Usage: lib.desktop.monitors.getDefaults config.monitors
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
  };
}
