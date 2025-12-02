# Docker container utilities for OCI container management
#
# Provides reusable patterns for Docker-based services including
# network management, service orchestration, and systemd integration.
#
# Usage:
#   lib.infra.containers.mkDockerNetwork { pkgs, name = "mynet"; }
#   lib.infra.containers.mkContainerTarget { name = "myapp"; }
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

  # Create a systemd service that manages a Docker network
  #
  # Arguments:
  #   pkgs: Nixpkgs instance (required for docker package)
  #   name: Network name (required)
  #   driver: Network driver (default: "bridge")
  #
  # Returns: Attrset suitable for systemd.services
  #
  # Usage:
  #   systemd.services = lib.infra.containers.mkDockerNetwork {
  #     inherit pkgs;
  #     name = "myapp";
  #   };
  #
  mkDockerNetwork =
    {
      pkgs,
      name,
      driver ? "bridge",
    }:
    {
      "docker-network-${name}" = {
        path = [ pkgs.docker ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStop = "docker network rm -f ${name}";
        };
        script = ''
          docker network inspect ${name} || docker network create --driver ${driver} ${name}
        '';
      };
    };

  # Create a systemd target for orchestrating container services
  #
  # Arguments:
  #   name: Target name (required)
  #   description: Target description (optional)
  #
  # Returns: Attrset suitable for systemd.targets
  #
  # Usage:
  #   systemd.targets = lib.infra.containers.mkContainerTarget {
  #     name = "myapp";
  #     description = "My application stack";
  #   };
  #
  mkContainerTarget =
    {
      name,
      description ? "Root target for ${name} container stack",
    }:
    {
      "docker-${name}-root" = {
        unitConfig = {
          Description = description;
        };
        wantedBy = [ "multi-user.target" ];
      };
    };

  # Generate extraOptions for container networking
  #
  # Arguments:
  #   useHostNetwork: Whether to use host networking (bool)
  #   networkName: Primary network name (string)
  #   networkAlias: Container alias on the network (string)
  #   extraNetworks: Additional networks to join (list of strings)
  #
  # Returns: List of Docker CLI options
  #
  mkNetworkOptions =
    {
      useHostNetwork ? false,
      networkName,
      networkAlias,
      extraNetworks ? [ ],
    }:
    if useHostNetwork then
      [ "--network=host" ]
    else
      [
        "--network=${networkName}"
        "--network-alias=${networkAlias}"
      ]
      ++ (map (net: "--network=${net}") extraNetworks);
}
