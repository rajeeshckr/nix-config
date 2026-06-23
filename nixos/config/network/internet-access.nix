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
  #     claw.rajeeshckr.uk       ← this file (OpenClaw agent; see nixos/desktop/openclaw.nix)
  #     auth.rajeeshckr.uk       ← nixos/desktop/authentik.nix
  #     grafana.rajeeshckr.uk    ← nixos/desktop/monitoring/default.nix
  #     ssh.rajeeshckr.uk        ← SSH→localhost:22, not nginx (see cloudflared.nix)
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
        # HTTP/2 disabled: the only HTTP/2 peer would be cloudflared on the
        # loopback hop, which gains nothing from h2 multiplexing. Leaving it
        # off sidesteps the HPACK "HTTP/2 Bomb" memory-exhaustion DoS
        # (blog.calif.io/p/codex-discovered-a-hidden-http2-bomb); the
        # max_headers fix only landed in nginx mainline 1.29.8 and we're on
        # the 1.28.x stable branch.
        http2 = false;
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
        # See the vault vhost above — HTTP/2 off to avoid the HPACK bomb DoS.
        http2 = false;
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

      # OpenClaw agent gateway — see nixos/desktop/openclaw.nix. The built-in
      # WebChat/Control UI lives at /openclaw and speaks WebSocket for the live
      # chat stream, so proxyWebsockets is mandatory. The gateway binds loopback
      # only; this vhost (reached via the Cloudflare Tunnel) is the public path.
      # Locking down WHO can reach it is done at the Cloudflare Access layer, not
      # here — this agent can run commands on the box.
      "claw.rajeeshckr.uk" = {
        # See the vault vhost above — HTTP/2 off to avoid the HPACK bomb DoS.
        http2 = false;
        locations."/" = {
          proxyPass = "http://127.0.0.1:18789";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host  $host;
            # Agent turns can stream for a while on a small local model.
            proxy_read_timeout 600s;
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
    # SSH (22) is intentionally NOT in the global list: public SSH goes
    # through the Cloudflare Tunnel (ssh.rajeeshckr.uk -> localhost:22,
    # gated by Cloudflare Access), and loopback ignores the firewall, so
    # the tunnel is unaffected. We still allow 22 on the LAN interface
    # below for direct `ssh 192.168.1.30` admin access.
    allowedTCPPorts = [ 80 443 8096 8000 7878 9000 ];
    allowedUDPPorts = [ 41641 ]; # Tailscale
    interfaces.wlp7s0.allowedTCPPorts = [ 22 ]; # SSH on LAN only
  };
}
