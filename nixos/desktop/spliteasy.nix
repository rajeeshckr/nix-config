# SplitEasy - expense splitting app
#
# Images must be built locally as root first:
#   sudo podman build -t spliteasy-backend:latest ~/spliteasy/backend
#   sudo podman build -t spliteasy-webclient:latest ~/spliteasy/web-client
#
# After rebuild, services are managed by systemd:
#   systemctl status podman-spliteasy-backend
#   systemctl status podman-spliteasy-webclient
#   journalctl -u podman-spliteasy-backend -f
#   journalctl -u podman-spliteasy-webclient -f
#
{ config
, lib
, pkgs
, ... }:
let
  cfg = {
    backend = {
      image = "localhost/spliteasy-backend:latest";
      port = 9090;
    };
    webclient = {
      image = "localhost/spliteasy-webclient:latest";
      port = 3000;
    };
    dataDir = "/var/lib/spliteasy";
  };
in {
  # Ensure data directory exists
  systemd.tmpfiles.rules = [
    "d ${cfg.dataDir} 0755 root root -"
  ];

  virtualisation.oci-containers.containers = {
    spliteasy-backend = {
      autoStart = true;
      image = cfg.backend.image;
      extraOptions = [
        "--pull=never"  # image is built locally, don't try to pull from a registry
      ];
      ports = ["${toString cfg.backend.port}:8080"];
      volumes = [
        "${cfg.dataDir}:/app/data:Z"
      ];
    };

    spliteasy-webclient = {
      autoStart = true;
      image = cfg.webclient.image;
      extraOptions = [
        "--pull=never"
      ];
      ports = ["${toString cfg.webclient.port}:80"];
    };
  };

  # Open firewall for both services
  networking.firewall.allowedTCPPorts = [ cfg.backend.port cfg.webclient.port ];
}
