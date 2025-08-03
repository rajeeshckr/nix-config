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
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  # Mount external SMB share
  fileSystems."/movies-indian" = {
    device = "//192.168.1.1/USB_Storage";
    fsType = "cifs";
    options = [
      "guest"             # Use guest account, no password needed
      "uid=1000"          # Mount as your user (run `id -u raj` to confirm)
      "gid=986"           # Mount as the 'users' group (run `id -g raj` to confirm)
      "iocharset=utf8"    # Character set for file names
      "nofail"            # Don't block boot if the share is unavailable
      "_netdev"           # This is a network device
      "x-systemd.automount" # Mount on first access
    ];
  };

  # Ensure cifs-utils is available for SMB mounting
  environment.systemPackages = with pkgs; [
    cifs-utils
  ];
}
