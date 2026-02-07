# SplitEasy backend - expense splitting app
#
# The container image must be built locally first:
#   podman build -t spliteasy-backend:latest ~/spliteasy/backend
#
# After rebuild, the service is managed by systemd:
#   systemctl status podman-spliteasy-backend
#   journalctl -u podman-spliteasy-backend -f
#
{ config
, lib
, pkgs
, ... }:
let
  cfg = {
    image = "localhost/spliteasy-backend:latest";
    port = 9090;
    dataDir = "/var/lib/spliteasy";
  };
in {
  # Ensure data directory exists
  systemd.tmpfiles.rules = [
    "d ${cfg.dataDir} 0755 root root -"
  ];

  virtualisation.oci-containers.containers.spliteasy-backend = {
    autoStart = true;
    image = cfg.image;
    extraOptions = [
      "--pull=never"  # image is built locally, don't try to pull from a registry
    ];
    ports = ["${toString cfg.port}:8080"];
    volumes = [
      "${cfg.dataDir}:/app/data:Z"
    ];
  };

  # Open firewall for the backend
  networking.firewall.allowedTCPPorts = [ cfg.port ];
}
