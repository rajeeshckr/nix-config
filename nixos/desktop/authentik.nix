{ config, ... }:

# Self-hosted SSO / IdP via the community `authentik-nix` flake.
#
# Why this exists:
#   - Apps that natively speak OIDC (Immich, Grafana, Jellyfin-with-plugin)
#     federate against this and stop owning their own user lists.
#   - Apps without any auth (Radarr, Sonarr, Bazarr, Jackett, Transmission)
#     get gated by an nginx `auth_request` against Authentik's "embedded
#     outpost" (a Proxy Provider configured per app in the UI).
#   - Vaultwarden is INTENTIONALLY left out — Bitwarden mobile/desktop/CLI
#     clients hit /api directly without browser cookies, so neither OIDC nor
#     forward-auth works for it. Keep its master-password auth as-is.
#
# Architecture:
#   browser/app
#       │  HTTPS  (TLS terminated at Cloudflare's edge — no ACME on origin)
#       ▼
#   Cloudflare edge → cloudflared (tunnel, dialed outbound by our box)
#       │  HTTP, loopback only
#       ▼
#   nginx :80   (vhost auth.rajeeshckr.uk, set up by services.authentik.nginx)
#       │  HTTPS, loopback only (authentik's self-signed cert; nginx
#       │  doesn't verify upstream certs by default)
#       ▼
#   authentik server :9443 + :9000  +  worker  +  embedded outpost
#       │
#       ├─ postgres (local, managed by the module)
#       └─ redis    (local, managed by the module)
#
# Secrets:
#   AUTHENTIK_SECRET_KEY lives in secrets/authentik-env.age (agenix). To
#   add SMTP later, decrypt → append AUTHENTIK_EMAIL__PASSWORD=… → re-encrypt.
#
# First-run:
#   1. After `update`, wait for ACME (~30s) and visit
#        https://auth.rajeeshckr.uk/if/flow/initial-setup/
#      to set the `akadmin` password. There is no declarative way to do
#      this — the upstream bootstrap flow is the supported path.
#   2. Configure providers/applications in the UI. Per-app integration
#      (Immich OIDC, Radarr forward-auth, etc.) is added in follow-up
#      commits — see doc/AUTHENTIK.md once it exists.
#
# DNS / routing:
#   auth.rajeeshckr.uk is fronted by the Cloudflare Tunnel (see
#   nixos/desktop/cloudflared.nix). The DNS entry is a proxied CNAME to
#   <tunnel-uuid>.cfargotunnel.com (auto-created when the Public Hostname
#   route is added in the Cloudflare dashboard). No ACME needed — TLS
#   terminates at the edge.

{
  age.secrets.authentik-env.file = ../../secrets/authentik-env.age;

  services.authentik = {
    enable = true;

    # Systemd EnvironmentFile — read at unit start, never lands in the
    # world-readable /nix/store.
    environmentFile = config.age.secrets.authentik-env.path;

    # The flake's nginx integration creates the auth.rajeeshckr.uk vhost
    # (proxying to authentik's internal HTTPS listener on :9443).
    # `enableACME = false` because we're behind a Cloudflare Tunnel that
    # terminates TLS at the edge — the origin vhost just listens on
    # plain HTTP on loopback :80 and is reached only via cloudflared.
    nginx = {
      enable = true;
      enableACME = false;
      host = "auth.rajeeshckr.uk";
    };

    settings = {
      disable_startup_analytics = true;
      avatars = "initials";
      # email = {
      #   host = "smtp.example.com";
      #   port = 587;
      #   username = "authentik@rajeeshckr.uk";
      #   use_tls = true;
      #   use_ssl = false;
      #   from = "authentik@rajeeshckr.uk";
      # };
    };
  };
}
