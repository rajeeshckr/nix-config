{ config, pkgs, ... }:

{
  # Tailscale — overlay network used to reach LAN-only services
  # (radarr / sonarr / jackett / transmission etc.) from the road.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "both";
  };

  # cloudflared (Cloudflare Tunnel) is installed but inactive until a tunnel
  # is configured. Currently unused — kept for the option of closing
  # router port-forwards 80/443 in future.
  services.cloudflared = {
    enable = true;
  };

  # Let's Encrypt for nginx vhosts below.
  security.acme = {
    acceptTerms = true;
    defaults.email = "rajeesh.ckr@gmail.com";
  };

  # Reverse proxy. Each public-facing service gets its own subdomain on
  # rajeeshckr.uk (DNS managed by Cloudflare, set to "DNS only" — grey
  # cloud — so HTTP-01 ACME challenges work and Cloudflare's free-plan
  # 100 MB upload cap doesn't bite Immich).
  #
  # Convention: one subdomain per service, proxied to the loopback port the
  # service already listens on. LAN clients can still hit the service
  # directly on its native port via 192.168.1.30:<port>.
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;

    virtualHosts = {
      "immich.rajeeshckr.uk" = {
        enableACME = true;
        forceSSL = true;
        # Immich uploads originals (raw photos, 4K video) — needs big body
        # size and long timeouts. nginx default of 1 MB will reject uploads
        # with HTTP 413.
        extraConfig = ''
          client_max_body_size 50000M;
          proxy_read_timeout   600s;
          proxy_send_timeout   600s;
          send_timeout         600s;
        '';
        locations."/" = {
          proxyPass = "http://127.0.0.1:2283";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host  $host;
            proxy_buffering        off;
            proxy_request_buffering off;
          '';
        };
      };

      "jellyfin.rajeeshckr.uk" = {
        enableACME = true;
        forceSSL = true;
        extraConfig = ''
          add_header X-Content-Type-Options "nosniff" always;
        '';
        locations."/" = {
          proxyPass = "http://127.0.0.1:8096";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Forwarded-For      $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto    $scheme;
            proxy_set_header X-Forwarded-Host     $host;
            proxy_set_header X-Forwarded-Protocol $scheme;
            proxy_buffering off;
          '';
        };
      };
    };
  };

  # Firewall:
  #   80/443  — public HTTP(S) for nginx (router forwards these from WAN)
  #   8096    — Jellyfin direct LAN access (TVs / clients on the same subnet)
  #   7878    — Radarr LAN access
  #   8000    — vLLM LAN access
  # Per-service ports for transmission / sonarr / jackett / bazarr are opened
  # by their own modules via `openFirewall = true`.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 8096 8000 7878 ];
    allowedUDPPorts = [ 41641 ]; # Tailscale
  };
}
