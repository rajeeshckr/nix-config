{ config, lib, pkgs, ... }:

# `immich-go` is added to systemPackages so we have a CLI to import Google
# Takeout / iCloud / etc. archives. It re-applies dates & GPS from JSON
# sidecars that Google strips out — needed for the timeline to be correct.

# Self-hosted photo/video backup (https://immich.app).
# Uses the native NixOS module (services.immich) instead of the upstream
# docker-compose stack — it provisions PostgreSQL (with the required
# pgvecto.rs / VectorChord extensions), Redis, the API server and the
# machine-learning sidecar in one go.
#
# Defaults expose the web UI on http://<host>:2283.
#
# After first boot:
#   1. Browse to http://<host>:2283 and create the admin account.
#   2. (Optional) Move the photo library by changing `mediaLocation` below;
#      anything already imported needs to be moved on disk by hand.

{
  services.immich = {
    enable = true;
    openFirewall = true;
    # Default `host` is "localhost", which only binds to loopback and makes
    # the LAN-facing port 2283 unreachable. Bind on all interfaces instead.
    host = "0.0.0.0";

    # Where uploaded originals, thumbnails and transcodes live.
    # Kept on the SSD by default for DB-adjacent IO; point at a path on
    # /media if you want the library on the mergerfs pool instead.
    mediaLocation = "/srv/data/immich";

    # Bundled ML container handles face recognition + smart search.
    machine-learning.enable = true;

    # Provision Postgres locally via the module.
    database = {
      enable = true;
      createDB = true;
    };

    # Provision Redis locally via the module.
    redis.enable = true;
  };

  # Make sure the parent of mediaLocation exists with the right ownership
  # before the immich service starts. The module itself creates
  # mediaLocation, but only if its parent is writable.
  systemd.tmpfiles.rules = [
    "d /srv/data 0755 root root - -"
    "d /srv/data/immich 0750 immich immich - -"
  ];

  environment.systemPackages = [ pkgs.immich-go ];
}
