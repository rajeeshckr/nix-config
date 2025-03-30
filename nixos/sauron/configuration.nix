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
      ./samba.nix
      ./unifi.nix
      ./mail.nix
      ./pvpgn.nix
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
      2049 # nfsv4
      111 2049 4000 4001 4002 20048 # nfs
      8384 22000 # syncthing
      80 443 8080 8443 # nginx
      22 # ssh via tailscale
      27015 # steam
      51413 # torrent
      8191 # flaresolverr
    ];
    allowedUDPPorts = [
      111 2049 4000 4001 4002 20048 # nfs
      22000 21027 # syncthing
      config.services.tailscale.port
      27015 # steam
      51413 # torrent
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

  services.nginx = {
    enable = true;

    # recommended settings
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;

    # Only allow PFS-enabled ciphers with AES256
    sslCiphers = "AES256+EECDH:AES256+EDH:!aNULL";

    # whitelisting
    commonHttpConfig = ''
    #allow 192.168.0.0/24;
    #allow 10.0.0.0/16;
    #allow 173.245.48.0/20;
    #allow 103.21.244.0/22;
    #allow 103.22.200.0/22;
    #allow 103.31.4.0/22;
    #allow 141.101.64.0/18;
    #allow 108.162.192.0/18;
    #allow 190.93.240.0/20;
    #allow 188.114.96.0/20;
    #allow 197.234.240.0/22;
    #allow 198.41.128.0/17;
    #allow 162.158.0.0/15;
    #allow 104.16.0.0/13;
    #allow 104.24.0.0/14;
    #allow 172.64.0.0/13;
    #allow 131.0.72.0/22;
    #deny all;

    # Add HSTS header with preloading to HTTPS requests.
    # Adding this header to HTTP requests is discouraged
    map $scheme $hsts_header {
        https   "max-age=31536000; includeSubdomains; preload";
    }
    add_header Strict-Transport-Security $hsts_header;

    # Enable CSP for your services.
    #add_header Content-Security-Policy "script-src 'self'; object-src 'none'; base-uri 'none';" always;

    # Minimize information leaked to other domains
    add_header 'Referrer-Policy' 'origin-when-cross-origin';

    # Disable embedding as a frame
    # breaks jellyfin on webOS
    # https://jellyfin.org/docs/general/networking/nginx/
    # - saml
    # add_header X-Frame-Options DENY;

    # Prevent injection of code in other mime types (XSS Attacks)
    add_header X-Content-Type-Options nosniff;

    # Enable XSS protection of the browser.
    # May be unnecessary when CSP is configured properly (see above)
    add_header X-XSS-Protection "1; mode=block";

    # This might create errors
    proxy_cookie_path / "/; secure; HttpOnly; SameSite=strict";
    '';

    virtualHosts."tv.samlockart.com" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
      };
    };
    virtualHosts."tv.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
      };
    };

    virtualHosts."www.iced.cool" = {
      # catch all
      forceSSL = true;
      enableACME = true;
      default = true;
      locations."/" = {
        return = 404;
      };
    };
    virtualHosts."open-webui.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.open-webui.port}";
        recommendedProxySettings = true;
      };
    };
    tailscaleAuth = {
      enable = true;
      virtualHosts = [
        "jackett.middleearth.samlockart.com"
      ];
    };
    virtualHosts."sonarr.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8989";
      };
    };
    virtualHosts."jackett.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:9117";
      };
    };
    virtualHosts."bazarr.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.bazarr.listenPort}";
      };
    };
    virtualHosts."radarr.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:7878";
      };
    };
    virtualHosts."sync.middleearth.samlockart.com" = {
      forceSSL = false;
      enableACME = false;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8384";
      };
    };
  };
  # accept the EULA
  security.acme.defaults.email = "sam@samlockart.com";
  security.acme.acceptTerms = true;
  
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
    nginx = {
      isSystemUser = true;
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

  services.pvpgn = {
    enable = true;
    bnetd = {
      servername = "WankNet";
      logFile = "/var/log/bnetd.log";
    };
    localStateDir = "/srv/data/pvpgn";
    openFirewall = true;
    news = ''
      {2024-10-16}

      Welcome to the jungle.
    '';
  };

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

    unifi = {
      image = "jacobalberty/unifi";
      ports = ["8081:8081" "8444:8444" "3478:3478/udp"];
      user = "unifi:unifi";
      volumes = ["/srv/data/unifi:/unifi"];
      environment = {
        TZ = "Australia/Melbourne";
        UNIFI_HTTP_PORT = "8081";
        UNIFI_HTTPS_PORT = "8444";
      };
    };
  };

  # Enable the OpenSSH daemon.
  services.openssh = {
    # support yubikey
    # https://developers.yubico.com/SSH/Securing_SSH_with_FIDO2.html
    extraConfig = ''
    PubkeyAuthOptions verify-required
    Match Group sftponly
      ChrootDirectory /srv/share/public
      ForceCommand internal-sftp
      AllowTcpForwarding no
  '';
  };

  # NFS
  services.nfs.server = {
    enable = true;
    # fixed rpc.statd port; for firewall
    lockdPort = 4001;
    mountdPort = 4002;
    statdPort = 4000;
    exports = ''
      /srv/share/sam          192.168.0.0/255.255.255.0(rw,fsid=0,no_subtree_check) 100.64.0.0/255.255.255.0(rw,fsid=0,no_subtree_check)
      /srv/share/emma         192.168.0.0/255.255.255.0(rw,fsid=0,no_subtree_check) 100.64.0.0/255.255.255.0(rw,fsid=0,no_subtree_check)
      /srv/share/public       192.168.0.0/255.255.255.0(rw,nohide,insecure,no_subtree_check) 100.64.0.0/255.255.255.0(rw,nohide,insecure,no_subtree_check)
      /srv/media              192.168.0.0/255.255.255.0(ro,nohide,insecure,no_subtree_check) 100.64.0.0/255.255.255.0(rw,nohide,insecure,no_subtree_check)
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

  ## alert on failure
  systemd.services = {
    "notify-problems@" = {
      enable = false; # need to fix sendgrid shit
      serviceConfig.User = "root";
      environment.SERVICE = "%i";
      script = ''
        printf "Content-Type: text/plain\r\nSubject: $SERVICE FAILED\r\n\r\n$(systemctl status $SERVICE)" | /run/wrappers/bin/sendmail root
      '';
    };
  };
  systemd.packages = [
    (pkgs.runCommandNoCC "notify.conf" {
      preferLocalBuild = true;
      allowSubstitutes = false;
    } ''
      mkdir -p $out/etc/systemd/system/service.d/
      echo -e "[Unit]\nOnFailure=notify-problems@%i.service\nStartLimitIntervalSec=1d\nStartLimitBurst=5\n" > $out/etc/systemd/system/service.d/notify.conf
      '')
  ];

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

  
  # manual host configuration
  networking.extraHosts =
    ''
      127.0.0.2 sync.samlockart.com
    '';


  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}

