# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../config/common
      ../config/network
      ../config/nvidia.nix
      ./maubot.nix
      ./mumble.nix
      ./borg.nix
      ./vaultwarden.nix
      ./transmission.nix
      ./nas.nix
      ./unifi.nix
      ./mail.nix
      ./pvpgn.nix
      ./nginx.nix
#      ../config/home-manager.nix # get working
    ];

  # Use the systemd-boot EFI boot loader.
  boot = {
    kernelModules = [ "wl" ];
    blacklistedKernelModules = [ "b43" "bcma" ];
    extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];
  };

  networking.hostName = "sauron"; # Define your hostname.
  networking.hostId = "acfb04f9"; # head -c 8 /etc/machine-id

  networking.networkmanager.enable = false;  # Easiest to use and most distros use this by default.
  networking.interfaces = {
    eno2 = {
        mtu = 9000;
    };
  };

  # firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      8384 22000 # syncthing
      22 # ssh via tailscale
      27015 # steam
      8191 # flaresolverr
    ];
    allowedUDPPorts = [
      22000 21027 # syncthing
      config.services.tailscale.port
      27015 # steam
      1900 7359 # dlna jellyfin
    ];
    # always allow traffic from your Tailscale network
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
  };

  ## services
  services.tailscaleAuth = {
    enable = true;
  };

  users.groups.emma = {};
  users.users = {
    emma = {
      isSystemUser = true;
      group = "emma";
    };
    # services
    syncthing = {
      isSystemUser = true;
      group = "syncthing";
    };
  };
  users.groups = {
    sftponly = {};
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    ipmiutil
    ipmitool
    steamcmd
    mailutils
    unstable.jellyfin
    unstable.jellyfin-web
    unstable.jellyfin-ffmpeg
    docker # todo - replace with podman
  ];

  # enable docker support
  virtualisation.docker = {
    enable = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };

  # selfhosted rarbg
  # https://github.com/mgdigital/rarbg-selfhosted
  virtualisation.oci-containers.containers = {
    rarbg = {
      image = "ghcr.io/mgdigital/rarbg-selfhosted:latest";
      ports = ["3333:3333"];
      volumes = ["/srv/data/rarbg_db.sqlite:/rarbg_db.sqlite"];
    };

    flaresolverr = {
      image = "ghcr.io/flaresolverr/flaresolverr:latest";
      ports = ["8191:8191"];
    };
  };

  services.openssh = {
    # support yubikey
    # https://developers.yubico.com/SSH/Securing_SSH_with_FIDO2.html
    extraConfig = ''
    PubkeyAuthOptions verify-required
  '';
  };

  services.open-webui = {
    enable = true;
    openFirewall = true;
    port = 11111;
    environment = {
      OLLAMA_API_BASE_URL = "http://desktop:11434";
    };
  };

  # Syncthing
  services.syncthing = {
    enable = true;
    user = "syncthing";
    dataDir = "/srv/vault";    # Default folder for new synced folders
    configDir = "/srv/data/syncthing";   # Folder for Syncthing's settings and keys
    overrideDevices = true;     # overrides any devices added or deleted through the WebUI
    overrideFolders = true;     # overrides any folders added or deleted through the WebUI
    guiAddress = "http://0.0.0.0:8384";
    settings = {
      # TODO: use declarative node configuration
      # https://wiki.nixos.org/wiki/Syncthing
      devices = {
        "laptop"   = { id = "5ATZ7LD-C3AYIMS-EXQZILG-2A743HY-4Y7ULQY-RODJR7F-GO43W6X-CLXDAAA"; };
        "desktop"   = { id = "F7G62MY-FWFWFNY-PYVBZQE-S4EXYDX-IIPF4AQ-YAKJVP3-4TZXCKT-NAUTJQU"; };
      };
      folders = {
        "vault" = {        # Name of folder in Syncthing, also the folder ID
           path = "/srv/vault";    # Which folder to add to Syncthing
           devices = [ "laptop" "desktop" ];      # Which devices to share the folder with
        };
      };
    };
  };

  services.jellyfin = {
    package = pkgs.unstable.jellyfin;
    enable = true;
    openFirewall = true;
    dataDir = "/srv/data/jellyfin";
    cacheDir = "/var/cache/jellyfin"; # leave on ssd
  };

  services.radarr = {
    enable = true;
    dataDir = "/srv/data/radarr";
    openFirewall = true;
  };
  users.users.radarr.extraGroups = ["transmission"];

  services.sonarr = {
    enable = true;
    dataDir = "/srv/data/sonarr";
    openFirewall = true;
  };
  users.users.sonarr.extraGroups = ["transmission"];

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

  services.tailscale.authKeyFile = config.age.secrets.tailscale-authkey.path;

  # secrets
  age = {
    identityPaths = ["/srv/vault/ssh_keys/id_rsa"]; # requires `/srv/vault` to be mounted before agenix can be used
    secrets = {
      tailscale-server = {
        file = ../../secrets/tailscale-server.age;
      };
      tailscale-authkey = {
        file = ../../secrets/tailscale-authkey.age;
      };
    };
  };

  # does not support automatic merging so cannot put these into modules
  nixpkgs.config.permittedInsecurePackages = [
    # for jackett
    "dotnet-sdk-6.0.428"
    "aspnetcore-runtime-6.0.36"
    # maubot
    "olm-3.2.16"
  ];

  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}

