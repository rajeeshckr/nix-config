{ config
, lib
, pkgs
, ... }:
let cfg = config.server;
in {

  services.transmission = {
    enable = true;
    openFirewall = true;
    settings = {
      home = "/srv/data/transmission";
      download-dir = "/srv/media/downloads";
      incomplete-dir = "/srv/media/downloads/.incomplete";
      trash-original-torrent-files = true;
      rpc-bind-address = "0.0.0.0";
      rpc-port = 9091;
      rpc-whitelist = "127.0.0.1,192.168.1.*";
      rpc-host-whitelist-enabled = false;
      rpc-authentication-required = false;
      ratio-limit = "0.0";
      ratio-limit-enabled = true;
    };
  };

  # lazily get around auth ratelimiting caused by
  # sonarr/friends accessing the UI with incorrect user/pass
  systemd.timers."transmission-restart" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1h";
      OnUnitActiveSec = "1h";
      Unit = "transmission-restart.service";
    };
  };

  systemd.services."transmission-restart" = {
    script = ''
      set -eu
      ${pkgs.systemd}/bin/systemctl restart transmission.service
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };
}
