{ config
, lib
, pkgs
, ... }:
let cfg = config.server;
in {
  services.samba-wsdd.enable = true; # make shares visible for windows 10 clients
  services.samba-wsdd.openFirewall = true;

  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "sauron";
        "netbios name" = "sauron";
        security = "user";
        "hosts allow" = "100.64. 192.168.0. 127.0.0.1 localhost ::1";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };
      public = {
        path = "/srv/share/public";
        browseable = "yes";
        writable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0664";
        "directory mask" = "2777";
        "force user" = "nobody";
        "force group" = "nogroup";
      };
      sam = {
        path = "/srv/share/sam";
        browseable = "no";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0600";
        "directory mask" = "0700";
        "force user" = "sam";
        "force group" = "root";
      };
      emma = {
        path = "/srv/share/emma";
        browseable = "no";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0600";
        "directory mask" = "0700";
        "force user" = "emma";
        "force group" = "root";
      };
      tv = {
        path = "/srv/media/tv";
        browseable = "yes";
        "read only" = "yes";
        "guest ok" = "yes";
        "create mask" = "0600";
        "directory mask" = "0700";
        "force user" = "nobody";
        "force group" = "nogroup";
      };
      movies = {
        path = "/srv/media/movies";
        browseable = "yes";
        "read only" = "yes";
        "guest ok" = "yes";
        "create mask" = "0600";
        "directory mask" = "0700";
        "force user" = "nobody";
        "force group" = "nogroup";
      };
      downloads = {
        path = "/srv/media/downloads";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "nobody";
        "force group" = "nogroup";
      };
    };
  };
}