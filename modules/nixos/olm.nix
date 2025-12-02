# OLM native tunneling client for Pangolin networks
#
# Connects your machine to Pangolin/Newt sites via WireGuard tunnels.
# Uses the native binary (not Docker) for direct system integration.
#
# Usage:
#   imports = [ inputs.mix-nix.nixosModules.olm ];
#   services.olm = {
#     enable = true;
#     id = "your-olm-id";
#     secretFile = config.sops.secrets.olm-secret.path;
#     endpoint = "https://pangolin.example.com";
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
  cfg = config.services.olm;
in
{
  options.services.olm = {
    enable = mkEnableOption "OLM tunneling client for Pangolin networks";

    autoStart = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to start OLM automatically at boot.
        Set to false for manual control via systemctl.
      '';
    };

    id = mkOption {
      type = types.str;
      description = "OLM client identifier for authentication.";
      example = "abc123xyz";
    };

    secret = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        OLM secret for authentication (plaintext).
        Consider using secretFile for better security with sops-nix or agenix.
      '';
    };

    secretFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a file containing the OLM secret.
        The file should contain just the secret value, no newlines.
        Preferred over the secret option for production use.
      '';
      example = "/run/secrets/olm-secret";
    };

    endpoint = mkOption {
      type = types.str;
      description = "Pangolin endpoint URL for WebSocket connection.";
      example = "https://pangolin.example.com";
    };

    endpointIP = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "1.12.123.123";
      description = ''
        Direct IP address for the endpoint to bypass DNS/proxy.
        When set, the module can add a hosts entry for the domain.
      '';
    };

    mtu = mkOption {
      type = types.int;
      default = 1280;
      description = "Network interface MTU.";
    };

    dns = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "1.1.1.1";
      description = "DNS server to use. If not set, uses system default.";
    };

    logLevel = mkOption {
      type = types.enum [
        "DEBUG"
        "INFO"
        "WARN"
        "ERROR"
        "FATAL"
      ];
      default = "INFO";
      description = "Logging verbosity level.";
    };

    pingInterval = mkOption {
      type = types.str;
      default = "3s";
      description = "Server ping frequency.";
    };

    pingTimeout = mkOption {
      type = types.str;
      default = "5s";
      description = "Ping response timeout.";
    };

    holepunch = mkOption {
      type = types.bool;
      default = false;
      description = "Enable NAT traversal (experimental).";
    };

    healthFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path for connection status tracking.";
    };

    interfaceName = mkOption {
      type = types.str;
      default = "olm0";
      description = "Name of the WireGuard interface to create.";
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to OLM config file (overrides other options).";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.fosrl-olm;
      defaultText = literalExpression "pkgs.fosrl-olm";
      description = "OLM package to use.";
    };

    enableGnomeExtension = mkOption {
      type = types.bool;
      default = false;
      description = "Enable GNOME Shell extension for toggling OLM from the panel.";
    };

    gnomeExtensionPackage = mkOption {
      type = types.package;
      default = pkgs.olm-toggle;
      defaultText = literalExpression "pkgs.olm-toggle";
      description = "GNOME extension package for OLM toggle.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.secret != null || cfg.secretFile != null || cfg.configFile != null;
        message = "services.olm: Either 'secret', 'secretFile', or 'configFile' must be set.";
      }
      {
        assertion = !(cfg.secret != null && cfg.secretFile != null);
        message = "services.olm: Cannot set both 'secret' and 'secretFile'. Choose one.";
      }
    ];

    systemd.services.olm = {
      description = "OLM tunneling client for Pangolin networks";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = mkIf cfg.autoStart [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10s";

        # Need root for WireGuard interface management
        User = "root";
        Group = "root";

        # Capabilities for network interface management
        AmbientCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_BIND_SERVICE"
          "CAP_NET_RAW"
        ];
        CapabilityBoundingSet = [
          "CAP_NET_ADMIN"
          "CAP_NET_BIND_SERVICE"
          "CAP_NET_RAW"
        ];

        # Network access
        PrivateNetwork = false;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
        ];

        # Filesystem hardening
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = optionals (cfg.healthFile != null) [ (dirOf cfg.healthFile) ];

        # Process hardening
        NoNewPrivileges = true;
        ProtectKernelTunables = false; # Need to modify network settings
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = false; # Go binaries may need this
        RestrictRealtime = true;
        RestrictSUIDSGID = true;

        # System call filtering
        SystemCallFilter = [
          "@system-service"
          "@network-io"
          "~@privileged"
          "~@resources"
        ];
        SystemCallArchitectures = "native";
      };

      script =
        let
          secretArg =
            if cfg.secretFile != null then
              ''--secret "$(cat ${cfg.secretFile})"''
            else if cfg.secret != null then
              ''--secret "${cfg.secret}"''
            else
              "";
        in
        if cfg.configFile != null then
          ''
            exec ${getExe cfg.package} --config ${cfg.configFile}
          ''
        else
          ''
            exec ${getExe cfg.package} \
              --id "${cfg.id}" \
              ${secretArg} \
              --endpoint "${cfg.endpoint}" \
              --mtu "${toString cfg.mtu}" \
              ${optionalString (cfg.dns != null) ''--dns "${cfg.dns}"''} \
              --log-level "${cfg.logLevel}" \
              --ping-interval "${cfg.pingInterval}" \
              --ping-timeout "${cfg.pingTimeout}" \
              --interface "${cfg.interfaceName}" \
              ${optionalString cfg.holepunch "--holepunch true"} \
              ${optionalString (cfg.healthFile != null) "--health-file ${cfg.healthFile}"}
          '';
    };

    # Open WireGuard port for NAT traversal
    networking.firewall = mkIf cfg.holepunch {
      allowedUDPPorts = [ 51820 ];
    };

    # GNOME extension for panel toggle
    environment.systemPackages = mkIf cfg.enableGnomeExtension [
      cfg.gnomeExtensionPackage
    ];

    # Polkit rule for passwordless toggle
    security.polkit.extraConfig = mkIf cfg.enableGnomeExtension (
      builtins.readFile "${cfg.gnomeExtensionPackage}/share/polkit-1/rules.d/olm-toggle.rules"
    );
  };
}
