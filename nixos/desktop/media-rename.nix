# media-rename.nix – Weekly cleanup of torrent-style filenames under /media.
#
# Runs every Saturday at 23:00.  Strips site prefixes (TamilRockers, etc.),
# quality tags (1080p, HDRip, x264, …), and bracket noise, leaving clean
# "Title (Year)" names.
#
# Manual usage (dry-run first!):
#   systemctl start media-rename          # run now
#   journalctl -u media-rename -e         # check logs
#
# To test without renaming anything:
#   python3 /path/to/media-rename.py --dry-run

{ pkgs, ... }:

{
  systemd.services.media-rename = {
    description = "Clean torrent-style filenames under /media";
    after = [ "media.mount" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    script = ''
      ${pkgs.python3}/bin/python3 ${./scripts/media-rename.py}
    '';
  };

  systemd.timers.media-rename = {
    description = "Run media-rename every Saturday night";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sat *-*-* 23:00:00";
      Persistent = true; # run on next boot if machine was off Saturday
    };
  };
}
