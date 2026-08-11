# Newt Docker container module for Pangolin tunnel client
#
# Runs Newt in a Docker container with full Docker socket access,
# enabling container network validation and orchestration features.
#
# Usage:
#   imports = [ inputs.mix-nix.nixosModules.newt ];
#   services.newt = {
#     enable = true;
#     id = "your-newt-id";
#     secretFile = config.sops.secrets.newt-secret.path;
#     pangolinEndpoint = "https://pangolin.example.com";
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
  cfg = config.services.newt;
  containers = lib.infra.containers;
  prepareNetworks = pkgs.writeScript "newt-prepare-networks" ''
    #!${lib.getExe pkgs.fish}
    if not ${pkgs.docker}/bin/docker network inspect ${escapeShellArg cfg.networkName} >/dev/null 2>&1
      ${pkgs.docker}/bin/docker network create --driver bridge ${escapeShellArg cfg.networkName}
      or exit 1
    end

    ${concatMapStringsSep "\n" (network: ''
      if not ${pkgs.docker}/bin/docker network inspect ${escapeShellArg network} >/dev/null 2>&1
        echo "Required Docker network ${escapeShellArg network} does not exist" >&2
        exit 1
      end
    '') cfg.extraNetworks}
  '';
in
{
  # Disable upstream native module to avoid conflicts
  # We use Docker for container orchestration features (network validation, etc.)
  disabledModules = [ "services/networking/newt.nix" ];

  options.services.newt = {
    enable = mkEnableOption "Newt Docker container service for Pangolin tunneling";

    id = mkOption {
      type = types.str;
      description = "Newt ID for authentication with Pangolin server.";
      example = "2ix2t8xk22ubpfy";
    };

    secret = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Newt secret for authentication (plaintext).
        Consider using secretFile for better security with sops-nix or agenix.
      '';
    };

    secretFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to an environment file containing NEWT_SECRET.
        The file should be in the format: NEWT_SECRET=your-secret-here
        Preferred over the secret option for production use with sops-nix or agenix.
      '';
      example = "/run/secrets/newt-env";
    };

    image = mkOption {
      type = types.str;
      default = "fosrl/newt";
      description = "Docker image to use for Newt container.";
    };

    pangolinEndpoint = mkOption {
      type = types.str;
      description = "Pangolin server endpoint URL.";
      example = "https://pangolin.example.com";
    };

    networkName = mkOption {
      type = types.str;
      default = "newt";
      description = "Docker network name for container communication.";
    };

    networkAlias = mkOption {
      type = types.str;
      default = "newt";
      description = "Network alias for the Newt container.";
    };

    useHostNetwork = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Use host networking instead of Docker bridge networks.
        Note: Disables container network validation features.
      '';
    };

    extraNetworks = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional Docker networks to connect the container to.";
      example = [
        "traefik"
        "apps"
      ];
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.secret != null || cfg.secretFile != null;
        message = "services.newt: Either 'secret' or 'secretFile' must be set.";
      }
      {
        assertion = !(cfg.secret != null && cfg.secretFile != null);
        message = "services.newt: Cannot set both 'secret' and 'secretFile'. Choose one.";
      }
    ];

    # Container definition
    virtualisation.oci-containers.containers."newt" = {
      image = cfg.image;
      cmd = [
        "--id"
        cfg.id
        "--endpoint"
        cfg.pangolinEndpoint
        "--docker-socket"
        "/var/run/docker.sock"
        "--native"
      ]
      ++ optionals (cfg.secret != null) [
        "--secret"
        cfg.secret
      ];

      # Mount Docker socket for container orchestration features
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock:rw"
      ];

      # Read secret from file if specified
      environmentFiles = optionals (cfg.secretFile != null) [ cfg.secretFile ];

      log-driver = "journald";
      user = "root:root";

      extraOptions = [
        "--privileged"
        "--cap-add=NET_ADMIN"
        "--cap-add=SYS_MODULE"
      ]
      ++ (
        if cfg.useHostNetwork then
          [ "--network=host" ]
        else
          [
            "--network=${cfg.networkName}"
            "--network-alias=${cfg.networkAlias}"
          ]
          ++ (map (net: "--network=${net}") cfg.extraNetworks)
      );
    };

    # Container service configuration
    systemd.services."docker-newt" = {
      serviceConfig =
        containers.serviceDefaults
        // optionalAttrs (!cfg.useHostNetwork) {
          # Recheck immediately before every start: Docker prune may remove idle networks.
          ExecStartPre = mkBefore [ "${prepareNetworks}" ];
        };
      partOf = [ "docker-newt-root.target" ];
      wantedBy = [ "docker-newt-root.target" ];
    };

    # A persistent prune timer may fire during boot. Let Newt claim its network first.
    systemd.services.docker-prune.after = mkIf config.virtualisation.docker.autoPrune.enable [
      "docker-newt-root.target"
    ];

    # Root target for orchestration
    systemd.targets."docker-newt-root" = {
      unitConfig.Description = "Newt Pangolin tunnel container stack";
      wantedBy = [ "multi-user.target" ];
    };
  };
}
