{ config
, lib
, pkgs
, ... }:
let cfg = config.server;
in {
  environment.systemPackages = with pkgs; [
    unstable.jellyfin
    unstable.jellyfin-web
    unstable.jellyfin-ffmpeg
  ];

  # `media` group historically created out-of-band; declare it so
  # `users.users.<svc>.extraGroups = ["media"]` actually takes effect.
  # GID 1000 matches the existing /etc/group entry.
  users.groups.media.gid = 1000;

  services.jellyfin = {
    package = pkgs.unstable.jellyfin;
    enable = true;
    openFirewall = true;
    dataDir = "/srv/data/jellyfin";
    cacheDir = "/var/cache/jellyfin"; # leave on ssd
  };

  services.radarr = {
    package = pkgs.unstable.radarr;
    enable = true;
    dataDir = "/srv/data/radarr";
    openFirewall = true;
  };
  users.users.radarr.extraGroups = ["transmission" "media"];

  services.sonarr = {
    enable = true;
    dataDir = "/srv/data/sonarr";
    openFirewall = true;
  };
  users.users.sonarr.extraGroups = ["transmission" "media"];

  # Preserve existing `media` group membership that was set up out-of-band,
  # now that we declare the group above (nix would otherwise drop these).
  # transmission's *primary* group is set to `media` in transmission.nix, so
  # we don't need it as an extra group here.
  users.users.jellyfin.extraGroups = ["media"];

  services.jackett = {
    enable = true;
    dataDir = "/srv/data/jackett";
    package = pkgs.unstable.jackett;
    openFirewall = true;
  };

  services.bazarr = {
    enable = true;
    openFirewall = true;
  };
  users.users.bazarr.extraGroups = ["sonarr" "radarr"];

  networking.firewall.allowedUDPPorts = [ 1900 7359 9117 7878 ]; # dlna
  networking.firewall.allowedTCPPorts = [
    8191 # flaresolverr
    9091 # transmission RPC/web UI (services.transmission.openFirewall only opens the peer port)
  ];

  # selfhosted rarbg
  # https://github.com/mgdigital/rarbg-selfhosted
  # virtualisation.oci-containers.containers = {
  #   rarbg = {
  #     image = "ghcr.io/mgdigital/rarbg-selfhosted:latest";
  #     ports = ["3333:3333"];
  #     volumes = ["/srv/data/rarbg_db.sqlite:/rarbg_db.sqlite"];
  #   };
  # };

  # FlareSolverr - bypass Cloudflare protection for Jackett
  virtualisation.oci-containers.containers.flaresolverr = {
    image = "ghcr.io/flaresolverr/flaresolverr:latest";
    ports = ["8191:8191"];
    environment = {
      LOG_LEVEL = "info";
      TZ = "Australia/Melbourne";
    };
  };
}
