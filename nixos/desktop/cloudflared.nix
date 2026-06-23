{ config, lib, pkgs, ... }:

# Cloudflare Tunnel — outbound-only HTTPS tunnel to Cloudflare's edge.
#
# Why this exists:
#   Wideband moved us behind CGNAT (router WAN is now 100.x), so inbound
#   80/443 from the internet no longer reaches the box. The tunnel dials
#   *out* to Cloudflare, so public hostnames work regardless of what the
#   ISP does upstream.
#
# Remote-managed flow (the "dashboard" approach in Cloudflare's docs):
#   the tunnel definition and its ingress (Public Hostname → origin) live
#   in the Cloudflare dashboard. NixOS just runs the connector with a
#   token. Chosen over the locally-managed flow because:
#     - one secret (the token) vs two (cert.json + per-tunnel credentials)
#     - new hostname routes don't need a rebuild
#     - the dashboard's "Connectors" page is the same source-of-truth UI
#       used to monitor tunnel health, which is convenient
#   Downside: ingress rules aren't in this repo. The list of routes is
#   documented under "Tunnel routes" below so it's not silently mutable.
#
# Provisioning (one-time):
#   1. Cloudflare dashboard → Zero Trust → Networks → Tunnels → Create
#      a tunnel. Name it e.g. `nixos-home`. Choose Cloudflared. Copy the
#      token from the install command (everything after `--token `).
#   2. Encrypt the token as an env-file line:
#        cd /etc/nixos/secrets
#        agenix -e cloudflared-token.age
#        # paste exactly one line:
#        #   TUNNEL_TOKEN=eyJh...
#   3. In the same tunnel's "Public Hostname" tab, add each route in
#      "Tunnel routes" below — all of them point at the box's nginx on
#      localhost:80, and nginx routes by Host header to the actual
#      backend (see nixos/config/network/internet-access.nix).
#   4. `git add secrets/cloudflared-token.age nixos/desktop/cloudflared.nix`
#      then `update`. cloudflared dials out and routes go live within
#      a few seconds.
#
# Tunnel routes (mirror this in the Cloudflare dashboard):
#   jellyfin.rajeeshckr.uk → HTTP → localhost:80
#   vault.rajeeshckr.uk    → HTTP → localhost:80
#   claw.rajeeshckr.uk     → HTTP → localhost:80  (OpenClaw agent; see openclaw.nix)
#   ssh.rajeeshckr.uk      → SSH  → localhost:22
#
# IMPORTANT for claw.rajeeshckr.uk: this fronts an agent that can run commands
# on the box (incl. nixos-rebuild). Gate it with a Cloudflare Access policy
# (Zero Trust → Access → Applications, Self-hosted, same hostname) before it
# is usable from the internet — email-OTP/Google restricted to your address at
# minimum, ideally an mTLS client-cert or WARP-device rule to bind it to your
# phone. See the security note in nixos/desktop/openclaw.nix.
#   (auth + grafana can be added later — they currently have their own
#    ACME-issued vhosts that don't work under CGNAT either, but moving
#    them through the tunnel is a separate change in their own files.)
#
# The ssh route is the odd one out: type SSH (not HTTP) pointing straight
# at openssh on localhost:22, bypassing nginx (nginx only speaks HTTP).
# Clients reach it with `cloudflared access ssh` as an SSH ProxyCommand —
# no inbound port is exposed, the connector proxies the TCP stream out
# over the existing QUIC tunnel. Gate it with a Cloudflare Access policy
# (Zero Trust → Access → Applications, type Self-hosted, same hostname)
# so the SSH port isn't reachable by anyone who merely knows the hostname;
# your SSH private key remains the second factor end-to-end.
#
# Caveat: Cloudflare Free plan rejects request bodies >100 MB with HTTP
# 413 — this is *not* configurable from our side. Fine for streams and
# vault syncs; the reason Immich was dropped (uploads were many-GB).

{
  age.secrets.cloudflared-token = {
    file = ../../secrets/cloudflared-token.age;
    # Owned by the system `cloudflared` user (created below) so the
    # tunnel service can read it without running as root.
    owner = "cloudflared";
    group = "cloudflared";
    mode = "0400";
  };

  users.users.cloudflared = {
    isSystemUser = true;
    group = "cloudflared";
    description = "Cloudflare Tunnel daemon";
  };
  users.groups.cloudflared = { };

  # Token-based connector. We intentionally do *not* use the upstream
  # `services.cloudflared` NixOS module: it's built around the
  # locally-managed flow (credentialsFile + ingress in Nix) and has no
  # first-class option for `--token` / `TUNNEL_TOKEN`.
  systemd.services.cloudflared-tunnel = {
    description = "Cloudflare Tunnel (remote-managed)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "notify";
      User = "cloudflared";
      Group = "cloudflared";

      # cloudflared reads TUNNEL_TOKEN from env. EnvironmentFile keeps
      # the token off the process command line (no `ps`-leak).
      EnvironmentFile = config.age.secrets.cloudflared-token.path;

      # `--metrics 127.0.0.1:0` picks a random loopback port for the
      # diagnostics endpoint — keeps it off the LAN without us having to
      # pick a port that might collide later. If we ever want to scrape
      # it from prometheus, pin a port instead.
      ExecStart =
        "${pkgs.cloudflared}/bin/cloudflared --no-autoupdate "
        + "tunnel --metrics 127.0.0.1:0 run";

      Restart = "always";
      RestartSec = "5s";

      # Defensive sandboxing — cloudflared is internet-facing and runs
      # 24/7 as a system service, so worth locking down.
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      SystemCallArchitectures = "native";
    };
  };
}
