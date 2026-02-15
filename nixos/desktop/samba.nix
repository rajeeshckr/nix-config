{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.server;
in
{

  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "smbnixMovies";
        "netbios name" = "smbnixMovies";
        "security" = "user";
        #"use sendfile" = "yes";
        #"max protocol" = "smb2";
        # note: localhost is the ipv6 localhost ::1
        "hosts allow" = "192.168.1. 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };
      "public" = {
        "path" = "/srv/data/radarr";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
      };
      # Exposes the mergerfs pool — mobile can copy torrent downloads here
      "media" = {
        "path" = "/media";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "raj";
      };
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  # Ensure cifs-utils is available for SMB mounting (if needed in future)
  environment.systemPackages = with pkgs; [
    cifs-utils
  ];
}
