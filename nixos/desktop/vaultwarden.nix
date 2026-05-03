{ config, lib, pkgs, ... }:

# NOTE: pinned to nixpkgs-unstable (via the `unstable-packages` overlay).
# nixpkgs 24.11 ships vaultwarden 1.33.2, which is missing the
# `MasterPasswordUnlock` field that Bitwarden Android 2026.x and newer
# expect in /api/sync. Symptom on the older server: Android client
# crashes on unlock with `MissingPropertyException: Missing the
# required MasterPasswordUnlock data property`. Track upstream from
# unstable until 25.05+ becomes our nixpkgs base.

# Self-hosted Bitwarden-compatible password manager.
#
# We run *Vaultwarden* (https://github.com/dani-garcia/vaultwarden), the
# Rust reimplementation of the Bitwarden server — works with the upstream
# Bitwarden browser extensions, mobile apps and CLI, but is small enough
# to run on a homelab box (no MS SQL, no .NET).
#
# Architecture:
#   browser/mobile client
#         │  HTTPS
#         ▼
#   nginx :443  (vault.rajeeshckr.uk, see nixos/config/network/internet-access.nix)
#         │  HTTP, loopback only
#         ▼
#   vaultwarden :8222
#         │
#         └─ sqlite at /var/lib/vaultwarden/db.sqlite3
#
# IMPORTANT:
#   Bitwarden clients refuse to connect to a non-HTTPS server URL, which is
#   why this lives behind the existing nginx + Let's Encrypt setup. Hitting
#   http://nixos:8222 from a browser works for poking around but you can't
#   actually configure a client against it.
#
# First-run checklist (after the first `update`):
#   1. Wait a few seconds for ACME to issue the cert for vault.rajeeshckr.uk.
#   2. Browse to https://vault.rajeeshckr.uk and click "Create account".
#      The first account is just a regular user — there is no separate
#      "owner" role in Vaultwarden.
#   3. Once your account(s) are created, flip `SIGNUPS_ALLOWED` to `false`
#      below and `update` again so the public form is closed.
#   4. (Optional) To enable the /admin panel for invites / config, generate
#      an Argon2-hashed admin token and drop it in /var/lib/vaultwarden.env:
#         vaultwarden hash            # prompts for a password, prints a hash
#         echo 'ADMIN_TOKEN=<paste-the-$argon2id$...-string>' \
#           | sudo tee /var/lib/vaultwarden.env
#         sudo chmod 600 /var/lib/vaultwarden.env
#      Then uncomment `environmentFile` below and `update`.
#
# Migrating away from NordPass:
#   NordPass can export to a CSV. In the Bitwarden web vault, go to
#   Tools → Import data → choose "NordPass (CSV)" and upload it. Don't
#   forget to delete the CSV afterwards.

{
  services.vaultwarden = {
    enable = true;

    # Track upstream — see top-of-file note for why.
    package = pkgs.unstable.vaultwarden;
    webVaultPackage = pkgs.unstable.vaultwarden.webvault;

    # sqlite is plenty for a single-household vault and means no extra DB
    # service to babysit. The sqlite file lives under /var/lib/vaultwarden
    # (StateDirectory of the systemd unit).
    dbBackend = "sqlite";

    # Nightly sqlite backup snapshot. The module wires up a systemd timer
    # that runs `sqlite3 .backup` into this directory.
    backupDir = "/srv/data/vaultwarden/backup";

    config = {
      # Public URL clients will be told to use. Must match the nginx vhost.
      DOMAIN = "https://vault.rajeeshckr.uk";

      # Bind on loopback only — nginx terminates TLS and proxies in.
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;

      # Public signup form is closed. Existing accounts log in fine; new
      # users have to be invited from the /admin panel (see env-file
      # section below for how to enable it). Flip to `true` temporarily
      # if you need to add a household member without setting up admin.
      SIGNUPS_ALLOWED = false;

      # Don't let just anyone with the public URL invite themselves into
      # an org — invites must come from an org owner.
      INVITATIONS_ALLOWED = true;

      # WebSocket notifications (real-time vault sync) — served on the
      # same HTTP port in modern vaultwarden, no extra port needed.
      WEBSOCKET_ENABLED = true;

      # Show the org / collection sharing UI. Harmless for a 1-user vault.
      ORG_CREATION_USERS = "all";
    };

    # ADMIN_TOKEN (and SMTP_PASSWORD if you wire up email later) live
    # outside the world-readable Nix store. See the first-run notes above
    # for how to populate this file. Uncomment once it exists, otherwise
    # the unit will fail to start because of the missing file.
    # environmentFile = "/var/lib/vaultwarden.env";
  };

  # Make sure the backup dir exists with the right ownership before the
  # backup timer fires for the first time. The module creates
  # /var/lib/bitwarden_rs itself, but not anything under /srv/data.
  systemd.tmpfiles.rules = [
    "d /srv/data 0755 root root - -"
    "d /srv/data/vaultwarden        0750 vaultwarden vaultwarden - -"
    "d /srv/data/vaultwarden/backup 0750 vaultwarden vaultwarden - -"
  ];

  # Firewall: deliberately *not* opening 8222 — only the nginx vhost on
  # 443 is reachable. If you ever want raw LAN access (e.g. to debug
  # without DNS), add 8222 to allowedTCPPorts in internet-access.nix.
}
