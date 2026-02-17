# Immich - Self-hosted photo & video backup (Google Photos alternative)
#
# After NixOS rebuild, access the web UI at: http://<your-ip>:2283
#
# Android setup:
#   1. Install "Immich" from Google Play Store / F-Droid
#   2. Open the app and set Server URL to http://<your-ip>:2283
#   3. Create an account (first user becomes admin)
#   4. Enable auto-backup in the app settings
#
# Useful commands:
#   systemctl status immich-server
#   systemctl status immich-machine-learning
#   journalctl -u immich-server -f
#
{ config, lib, pkgs, ... }:

{
  services.immich = {
    enable = true;
    port = 2283;
    host = "0.0.0.0";             # listen on all interfaces (for Android access)
    openFirewall = true;           # allow port 2283 through the firewall
    mediaLocation = "/media/immich"; # store photos on the mergerfs pool
  };

  # Ensure the media directory exists on the storage pool
  systemd.tmpfiles.rules = [
    "d /media/immich 0750 immich immich -"
  ];
}
