# OCI container stack orchestration module
#
# Abstracts Docker container orchestration boilerplate by generating
# network services, systemd service configuration, and root targets
# from simple stack definitions.
#
# Usage:
#   imports = [ inputs.mix-nix.nixosModules.oci-stacks ];
#   virtualisation.oci-stacks.myapp = {
#     containers.myapp = {
#       image = "myapp:latest";
#       extraOptions = [
#         "--network=myapp"
#         "--network-alias=myapp"
#       ];
#     };
#     # network defaults to stack name
#   };
#
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  containers = lib.infra.containers;

  # Network submodule for full configuration
  networkSubmodule = types.submodule {
    options = {
      name = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Network name. Defaults to stack name if null.";
      };

      driver = mkOption {
        type = types.str;
        default = "bridge";
        description = "Docker network driver.";
      };

      subnet = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Network subnet for custom network configuration.";
        example = "10.1.1.0/24";
      };

      gateway = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Network gateway IP.";
        example = "10.1.1.1";
      };

      script = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = ''
          Custom script for network creation. Overrides auto-generated script.
          Use this for complex network configurations not covered by other options.
        '';
      };

      external = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          External network names to add as soft dependencies.
          These networks are expected to be created by other stacks.
          Container services will use 'wants' (not 'requires') for these.
        '';
      };
    };
  };

  # Network type: either string shorthand or full submodule
  networkType = types.either types.str networkSubmodule;

  # Normalize network config to always be an attrset
  normalizeNetwork =
    stackName: net:
    if builtins.isString net then
      {
        name = net;
        driver = "bridge";
        subnet = null;
        gateway = null;
        script = null;
        external = [ ];
      }
    else
      {
        name = if net.name != null then net.name else stackName;
        inherit (net)
          driver
          subnet
          gateway
          script
          external
          ;
      };

  # Stack submodule
  stackType = types.submodule (
    { name, config, ... }:
    {
      options = {
        containers = mkOption {
          type = types.attrsOf types.attrs;
          default = { };
          description = ''
            Container definitions. These are passed through to
            virtualisation.oci-containers.containers with orchestration added.
            Type validation is handled by oci-containers module.
          '';
        };

        network = mkOption {
          type = networkType;
          default = name;
          description = ''
            Network configuration for this stack.
            Can be a string (network name with defaults) or an attrset for full control.
          '';
          example = {
            name = "mynet";
            subnet = "10.1.1.0/24";
            gateway = "10.1.1.1";
          };
        };

        description = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Description for the systemd root target.";
          example = "My application container stack";
        };
      };
    }
  );

  # Generate network creation script
  mkNetworkScript =
    net:
    if net.script != null then
      net.script
    else
      ''
        docker network inspect ${net.name} || docker network create \
          --driver ${net.driver} \
          ${optionalString (net.subnet != null) "--subnet ${net.subnet}"} \
          ${optionalString (net.gateway != null) "--gateway ${net.gateway}"} \
          ${net.name}
      '';

  # Generate systemd services for a single stack
  mkStackServices =
    stackName: stackCfg:
    let
      net = normalizeNetwork stackName stackCfg.network;
      targetName = "docker-compose-${stackName}-root";
      containerNames = attrNames stackCfg.containers;
      externalNetServices = map (n: "docker-network-${n}.service") net.external;
    in
    # Container service extensions
    listToAttrs (
      map (containerName: {
        name = "docker-${containerName}";
        value = {
          serviceConfig = containers.serviceDefaults;
          after = [ "docker-network-${net.name}.service" ] ++ externalNetServices;
          requires = [ "docker-network-${net.name}.service" ];
          wants = externalNetServices;
          partOf = [ "${targetName}.target" ];
          wantedBy = [ "${targetName}.target" ];
        };
      }) containerNames
    )
    // {
      # Network service
      "docker-network-${net.name}" = {
        path = [ pkgs.docker ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStop = "${pkgs.docker}/bin/docker network rm -f ${net.name}";
        };
        script = mkNetworkScript net;
        partOf = [ "${targetName}.target" ];
        wantedBy = [ "${targetName}.target" ];
      };
    };

  # Generate systemd target for a single stack
  mkStackTarget =
    stackName: stackCfg:
    let
      targetName = "docker-compose-${stackName}-root";
    in
    {
      "${targetName}" = {
        unitConfig.Description = stackCfg.description or "OCI stack: ${stackName}";
        wantedBy = [ "multi-user.target" ];
      };
    };

  # Reference to our config (evaluated lazily per-path)
  cfg = config.virtualisation.oci-stacks;

in
{
  options.virtualisation.oci-stacks = mkOption {
    type = types.attrsOf stackType;
    default = { };
    description = ''
      OCI container stacks with automatic orchestration.

      Each stack gets:
      - Containers passed through to virtualisation.oci-containers
      - A Docker network service
      - Service configuration with restart policies
      - Network dependencies wired up
      - A root systemd target for orchestration
    '';
    example = literalExpression ''
      {
        myapp = {
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
      }
    '';
  };

  # Each path is a separate lazy thunk - avoids forcing full cfg evaluation upfront
  config = {
    # Passthrough all containers to oci-containers
    virtualisation.oci-containers.containers = lib.concatMapAttrs (_name: stack: stack.containers) cfg;

    # Generate services for each stack (merged via concatMapAttrs)
    systemd.services = lib.concatMapAttrs mkStackServices cfg;

    # Generate targets for each stack
    systemd.targets = lib.concatMapAttrs mkStackTarget cfg;
  };
}
