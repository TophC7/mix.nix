# Docker container utilities for OCI container management
#
# Provides service configuration defaults for container systemd units.
# For full stack orchestration, use the virtualisation.oci-stacks module.
#
{ lib }:

with lib;

{
  # Default systemd service configuration for containers
  # Provides sensible restart policies and timing
  #
  # Usage:
  #   systemd.services."docker-foo".serviceConfig = lib.infra.containers.serviceDefaults;
  #
  serviceDefaults = {
    Restart = mkOverride 90 "always";
    RestartMaxDelaySec = mkOverride 90 "1m";
    RestartSec = mkOverride 90 "100ms";
    RestartSteps = mkOverride 90 9;
  };
}
