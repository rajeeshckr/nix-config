# media-rename.nix - LLM-driven cleanup of messy filenames under /media/movies.
#
# Runs daily at 04:00 (randomized +30m). Uses a small local LLM (qwen2.5:3b via
# Ollama) to extract "Title (Year)" from torrent-style names, then renames the
# file/directory in place. After successful renames it triggers a Jellyfin
# library refresh so the UI updates immediately.
#
# Manual usage:
#   sudo systemctl start media-rename            # one-shot run with --apply
#   sudo -u media-rename media-rename --dry-run  # preview, no changes
#   journalctl -u media-rename -e                # check logs
#
# The Jellyfin API key is stored as an agenix secret (jellyfin-api-key.age)
# in env-file format (`JELLYFIN_API_KEY=...`); the service reads it via
# systemd EnvironmentFile and never writes it to disk in plaintext.

{ config, pkgs, lib, ... }:

let
  mediaRename = pkgs.writers.writePython3Bin "media-rename" {
    # No third-party imports; pure stdlib.
    # Disable opinionated style checks the writer otherwise enforces.
    flakeIgnore = [
      "E265" # block comment must start with '# ' (clashes with shebang)
      "E501" # line too long
      "W503" # line break before binary operator
      "E203" # whitespace before ':'
    ];
  } (builtins.readFile ./scripts/media-rename.py);
in
{
  age.secrets.jellyfin-api-key.file = ../../secrets/jellyfin-api-key.age;

  # System user so the service isn't root.
  users.users.media-rename = {
    isSystemUser = true;
    group = "media";
    description = "media-rename service user";
  };

  environment.systemPackages = [ mediaRename ];

  systemd.services.media-rename = {
    description = "Clean messy filenames under /media/movies via local LLM";
    # Wait until mergerfs and ollama are both available.
    after = [ "media.mount" "ollama.service" "network-online.target" ];
    wants = [ "ollama.service" "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "media-rename";
      Group = "media";
      # Reads JELLYFIN_API_KEY=... from the decrypted agenix secret.
      EnvironmentFile = config.age.secrets.jellyfin-api-key.path;
      # Sandbox: read-write only the dirs we need to actually rename inside,
      # plus our RuntimeDirectory for the lockfile. Everything else is RO/hidden.
      RuntimeDirectory = "media-rename";
      ReadWritePaths = [
        "/media-disk1"
        "/media-disk2"
        "/media-usb"
      ];
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      # Default: run with --apply (autonomous). Override on the CLI to dry-run.
      ExecStart = "${mediaRename}/bin/media-rename --apply --path /media/movies";
    };
  };

  systemd.timers.media-rename = {
    description = "Run media-rename daily at 04:00";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      RandomizedDelaySec = "30m";
      Persistent = true; # run on next boot if 04:00 was missed
      Unit = "media-rename.service";
    };
  };
}
