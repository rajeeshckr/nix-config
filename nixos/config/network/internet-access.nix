{ config, pkgs, ... }:

{
  # Tailscale — overlay network used to reach LAN-only services
  # (radarr / sonarr / jackett / transmission etc.) from the road.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "both";
  };

  # Let's Encrypt — kept enabled because `security.acme` has no harm when
  # no vhost references it. All current public vhosts are Cloudflare-Tunnel
  # fronted (TLS terminated at the edge), so nothing actually requests an
  # ACME cert right now. Leave the block in place so a future direct vhost
  # can opt into ACME by just setting `enableACME = true;` on its own line.
  security.acme = {
    acceptTerms = true;
    defaults.email = "rajeesh.ckr@gmail.com";
  };

  # Reverse proxy. All public-facing services run behind a Cloudflare Tunnel:
  #
  #     client → Cloudflare edge (HTTPS) → cloudflared (QUIC tunnel)
  #            → nginx :80 (loopback, HTTP-only) → backend
  #
  # Each vhost listens HTTP-only — no ACME, no forceSSL. TLS terminates at
  # Cloudflare's edge using its Universal SSL cert for *.rajeeshckr.uk.
  # Keeping nginx in the chain (rather than pointing cloudflared straight
  # at each backend) means proxy_set_header, proxyWebsockets,
  # client_max_body_size and other per-service knobs stay declarative
  # here, not duplicated into the Cloudflare dashboard.
  #
  # Public hostnames currently routed (kept in sync with the dashboard's
  # "Public Hostname" tab on the nixos-home tunnel):
  #     jellyfin.rajeeshckr.uk   ← this file
  #     vault.rajeeshckr.uk      ← this file
  #     auth.rajeeshckr.uk       ← nixos/desktop/authentik.nix
  #     grafana.rajeeshckr.uk    ← nixos/desktop/monitoring/default.nix
  #
  # LAN clients can still hit each service directly on its native port via
  # 192.168.1.30:<port> (no Cloudflare in the path, no TLS, full LAN speed).
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;

    virtualHosts = {
      # Vaultwarden (Bitwarden-compatible) — see nixos/desktop/vaultwarden.nix.
      # Bitwarden clients (browser ext, mobile, CLI) require HTTPS, so this
      # vhost is the only way to actually use the vault from outside the LAN.
      # The websocket path piggybacks on the same port in modern vaultwarden
      # — `proxyWebsockets` plus the Upgrade/Connection headers below cover
      # both /api and /notifications/hub.
      "vault.rajeeshckr.uk" = {
        # Vaultwarden allows attachments up to 128 MiB by default, but
        # Cloudflare Free caps request bodies at 100 MB — set the nginx
        # limit below that so a 413 has a chance to come from us with a
        # legible error rather than from Cloudflare's edge first.
        extraConfig = ''
          client_max_body_size 95M;
        '';
        locations."/" = {
          proxyPass = "http://127.0.0.1:8222";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host  $host;
          '';
        };
      };

      "jellyfin.rajeeshckr.uk" = {
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
  #   9000    — Authentik direct LAN access (skip nginx vhost / cert hassle for
  #             admin actions; the public path is still https://auth.rajeeshckr.uk)
  # Per-service ports for transmission / sonarr / jackett / bazarr are opened
  # by their own modules via `openFirewall = true`.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 8096 8000 7878 9000 ];
    allowedUDPPorts = [ 41641 ]; # Tailscale
  };
}
