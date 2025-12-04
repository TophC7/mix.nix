# Docker container utilities for OCI container management
#
# Provides service configuration defaults for container systemd units.
# For full stack orchestration, use the virtualisation.oci-stacks module.
#
{ lib }:

with lib;

{
  # Container utilities namespace
  containers = {
    # Default systemd service configuration for containers
    # Provides sensible restart policies and timing
    # Uses mkDefault so user-defined values take precedence
    #
    # Usage:
    #   systemd.services."docker-foo".serviceConfig = lib.infra.containers.serviceDefaults;
    #
    serviceDefaults = {
      Restart = mkDefault "always";
      RestartMaxDelaySec = mkDefault "1m";
      RestartSec = mkDefault "100ms";
      RestartSteps = mkDefault 9;
    };
  };
}
