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
#       │  HTTPS
#       ▼
#   nginx :443  (auth.rajeeshckr.uk, ACME via existing wildcard setup)
#       │  HTTP, loopback only
#       ▼
#   authentik server :9000  +  worker  +  embedded outpost :9000/outpost.goauthentik.io
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
# DNS:
#   Add an A record for `auth.rajeeshckr.uk` in Cloudflare (DNS-only /
#   grey cloud, same convention as the other rajeeshckr.uk subdomains)
#   pointing at the home WAN IP, before the first rebuild. ACME HTTP-01
#   will fail without it.

{
  age.secrets.authentik-env.file = ../../secrets/authentik-env.age;

  services.authentik = {
    enable = true;

    # Systemd EnvironmentFile — read at unit start, never lands in the
    # world-readable /nix/store.
    environmentFile = config.age.secrets.authentik-env.path;

    # The flake's nginx integration creates the vhost, requests an ACME
    # cert, and points authentik's internal cert-discovery at the issued
    # files. Discovery runs on a 1-hour timer, so the very first issuance
    # may take a moment to show up in the Authentik UI's Certificates page.
    nginx = {
      enable = true;
      enableACME = true;
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
