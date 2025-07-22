{ config, pkgs, ... }:

{

  age.secrets.ddclient-password.file = ../../../secrets/ddclient-password.age;
  
  # Enable Tailscale Funnel to expose services through Tailscale
  services.tailscale = {
    enable = true;
    openFirewall = true;
    # Enable experimental features (needed for Funnel)
    useRoutingFeatures = "both";
  };

  services.cloudflared = {
    enable = true;
  };

  # Set up Dynamic DNS with ddclient
  services.ddclient = {
    enable = false;
    domains = [ "rajeeshckr.ddnsgeek.com" ];
    username = "rajeesh.ckr@gmail.com";
    passwordFile = config.age.secrets.ddclient-password.path;
    protocol = "dyndns2"; # Adjust based on your DDNS provider
    server = "members.dyndns.org"; # Adjust based on your DDNS provider
    interval = "5min";
    use = "web";
  };

  # # Enable NAT and port forwarding
  # networking.nat = {
  #   enable = true;
  #   internalInterfaces = ["ve-+"];
  #   externalInterface = "enp6s0"; # Your external interface from configuration.nix
  # };

  # Automatically obtain and renew SSL certificates from Let's Encrypt
  security.acme = {
    acceptTOS = true;
    defaults.email = "rajeesh.ckr@gmail.com";
  };

  # Setup Nginx as a reverse proxy for your services
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    
    virtualHosts = {
      "rajeeshckr.ddnsgeek.com" = { # Your domain
        enableACME = true; # Enable automatic certificate generation
        forceSSL = true;   # Redirect all HTTP traffic to HTTPS
        # This will proxy requests from /jellyfin/ to your Jellyfin service
        locations."/jellyfin/" = {
          proxyPass = "http://127.0.0.1:8096/"; # The trailing slash is important here
          proxyWebsockets = true; # Required for Jellyfin
        };
      };
      # Add more virtual hosts for other services as needed
    };
  };

  # Open specific ports in the firewall for services you want to expose
  networking.firewall = {
    enable = true; # Enable the firewall with specific rules
    allowedTCPPorts = [ 80 443 8096 8000 ]; # HTTP, HTTPS, Jellyfin, test server
    allowedUDPPorts = [ 41641 ]; # Tailscale
  };
}
