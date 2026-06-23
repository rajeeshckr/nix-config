{ config, lib, pkgs, ... }:

# OpenClaw — a self-hosted, agentic AI assistant you talk to from a phone.
#
# What this gives you:
#   A ChatGPT-like web window (OpenClaw's built-in Control UI / WebChat) backed
#   by the *local* ollama model on this box, where the agent can actually run
#   commands on the host — "is jellyfin healthy?", "install <pkg>", "rebuild" —
#   reachable from your phone over the existing Cloudflare Tunnel.
#
# Architecture:
#   phone browser
#         │  HTTPS  (gated by a Cloudflare Access policy — see below)
#         ▼
#   Cloudflare edge ──QUIC──► cloudflared (nixos/desktop/cloudflared.nix)
#         │  HTTP :80, Host = claw.rajeeshckr.uk
#         ▼
#   nginx vhost (nixos/config/network/internet-access.nix)
#         │  HTTP + WS, loopback only
#         ▼
#   openclaw gateway  127.0.0.1:18789   ← Control UI/WebChat + OpenAI /v1 + WS
#         ├──► ollama 127.0.0.1:11434   (the LLM brain: qwen2.5:7b)
#         └──► host tools (bash/process) + scoped sudo (systemctl, nixos-rebuild…)
#
# Why a hand-rolled systemd unit (not a services.openclaw module):
#   nixpkgs ships `openclaw` only as a package, with no NixOS module. So we run
#   the gateway daemon ourselves, same shape as cloudflared.nix.
#
# Why pkgs.unstable.openclaw:
#   Our nixpkgs base is 24.11 (late 2024); OpenClaw didn't exist then. The
#   package only lives in nixpkgs-unstable, surfaced here via the
#   `unstable-packages` overlay (same pattern as ollama-cuda in llm.nix).
#
# SECURITY — read before exposing:
#   This endpoint can run commands on the host as the `openclaw` user, which has
#   passwordless sudo for a curated command set (below) including nixos-rebuild.
#   That is exactly what was asked for ("full power"), but it means anyone who
#   gets past the front door can drive the box. Defenses, outermost first:
#     1. Cloudflare Access policy on claw.rajeeshckr.uk (Zero Trust → Access →
#        Applications, Self-hosted). Start with email-OTP / Google restricted to
#        your address; add an mTLS client-cert or WARP-device rule to bind it to
#        your phone specifically. This is the "guard it with Cloudflare" layer.
#     2. OpenClaw's own gateway token (OPENCLAW_GATEWAY_TOKEN, agenix secret) —
#        required to open a Control UI/WebChat session.
#     3. The agent runs unprivileged by default; only the explicit sudo allowlist
#        below is reachable (no blanket root).
#   Do NOT install ClawHub skills — treat them as untrusted code.

let
  port = 18789;
  publicOrigin = "https://claw.rajeeshckr.uk";
  stateDir = "/var/lib/openclaw";
  workspace = "${stateDir}/workspace";

  # Declarative OpenClaw config. Written to ~/.openclaw/openclaw.json on each
  # start (our source of truth; OpenClaw keeps mutable state — sessions,
  # models.json — in sibling files it manages itself).
  openclawConfig = {
    gateway = {
      mode = "local";
      bind = "loopback"; # 127.0.0.1 only; nginx fronts it
      inherit port;
      # Token auth. This placeholder is substituted with the real token from
      # the agenix EnvironmentFile by the ExecStartPre script below, so the
      # secret never lands in the world-readable Nix store. (OpenClaw does not
      # adopt OPENCLAW_GATEWAY_TOKEN as the auth token on its own — left unset
      # it just generates a throwaway token on every start.)
      auth = {
        mode = "token";
        token = "@OPENCLAW_GATEWAY_TOKEN@";
      };
      # nginx terminates the loopback hop and injects X-Forwarded-* headers.
      trustedProxies = [ "127.0.0.1" ];
      controlUi = {
        enabled = true;
        basePath = "/openclaw";
        # REQUIRED for a public (non-loopback) browser origin, otherwise the
        # Control UI WebSocket connect is rejected.
        allowedOrigins = [ publicOrigin ];
      };
    };

    # Point OpenClaw at the local ollama. Native Ollama API (NO /v1 suffix) +
    # `api: "ollama"` is what makes tool calling reliable; the /v1 OpenAI-compat
    # path is explicitly discouraged by upstream for tool use. Defining an
    # explicit provider entry disables auto-discovery, so the model list is
    # spelled out here. `apiKey: "ollama-local"` is an accepted non-secret local
    # marker for loopback base URLs.
    models = {
      mode = "merge";
      providers.ollama = {
        baseUrl = "http://127.0.0.1:11434";
        apiKey = "ollama-local";
        api = "ollama";
        models = [
          {
            id = "qwen2.5:7b"; # tool-calling model already pulled in llm.nix
            name = "Qwen2.5 7B";
          }
        ];
      };
    };

    agents.defaults = {
      model.primary = "ollama/qwen2.5:7b";
      inherit workspace;
    };
  };

  configFile = (pkgs.formats.json { }).generate "openclaw.json" openclawConfig;

  # Seeds the agent's working knowledge about *this* box on first run. Copied
  # only if absent so the agent (or you) can evolve it later without it being
  # clobbered on every restart.
  agentsMd = pkgs.writeText "openclaw-AGENTS.md" ''
    # This host

    You are an assistant running directly on the NixOS server `nixos`
    (a home server/workstation). You have shell access via your `bash` tool,
    and passwordless `sudo` for a curated set of commands.

    ## How to do things here
    - This is NixOS. There is no apt/dnf. Software and services are declared in
      the flake at `/etc/nixos` and applied with a rebuild.
    - Rebuild the system after editing config:
      `sudo nixos-rebuild switch --flake /etc/nixos#nixos`
      (the human runs this as the `update` alias). Use
      `sudo nixos-rebuild test --flake /etc/nixos#nixos` to try a change without
      making it the boot default.
    - New/renamed `.nix` files must be `git add`-ed in `/etc/nixos` before a
      rebuild sees them (the flake reads the git tree).
    - To add a system package: add it to `environment.systemPackages` in
      `nixos/desktop/configuration.nix`, `git add` if new file, then rebuild.

    ## Checking on services (all systemd units)
    - Status:   `systemctl status <unit>`   e.g. `jellyfin`, `radarr`, `sonarr`,
                `transmission`, `ollama`, `cloudflared-tunnel`, `nginx`.
    - Logs:     `journalctl -u <unit> -e --no-pager`
    - Failed:   `systemctl --failed`
    - GPU:      `nvidia-smi`
    - Disk:     `df -h /`   (service data lives under `/srv/data/<service>`;
                bulk media under `/media`, which is nearly-full pooled HDDs —
                don't fill `/`).

    ## 1TamilMV weekly movie digest
    A systemd timer scans 1TamilMV's Tamil/Telugu/Malayalam/Hindi forums every
    Friday for new releases (it only collects — it never downloads). You help the
    human review and selectively download these. Three commands are on your PATH:
    - `tamilmv-pending` — show this week's not-yet-actioned releases, grouped by
      language, each with a numeric id. Run this when the human asks "what's new
      on tamilmv?" (or similar). Add `--all` to include already-grabbed items.
    - `tamilmv-grab <id> [quality]` — resolve the magnet for that topic and add it
      to transmission (downloads to /media/downloads). Quality defaults to
      `1080p`; pass e.g. `720p` or `any` (largest) to override. Use
      `tamilmv-grab <id> --list` to preview the available qualities/sizes first.
    - `tamilmv-search "<title>"` — search ALL of 1TamilMV (any age, any day),
      not just this week's digest. Use this whenever the human asks to download
      a specific movie that isn't in `tamilmv-pending` (e.g. "download Ghilli").
      Prints id-tagged matches; you then `tamilmv-grab <id>` the one they pick.
      Supports `--limit N` and `--json`.
    - `tamilmv-scan` — manually refresh the digest (the Friday timer runs this).
    - `tamilmv-mirror` — print the current live mirror vs the compiled-in
      fallback (`--check` exits non-zero on drift).

    Answering "download <movie>" on any day: run `tamilmv-search "<movie>"`,
    show the human the matches (there are usually several quality/source
    variants), and grab the id they choose. Only the weekly digest is limited
    to the last 7 days; search is not.

    Spelling: 1TamilMV's own search is literal, so first fix any obvious typo
    yourself (you know "drishyaam" means Drishyam). As a safety net,
    `tamilmv-search` ALSO auto-spell-corrects via Wikipedia when the raw query
    finds nothing — its output then shows "spell-corrected" and, if the
    correction was ambiguous, a "NOTE: other possible titles: …" line. When you
    see that NOTE (or aren't confident the corrected film is the one they
    meant), ASK the human which title they meant before grabbing — a typo can
    resolve to the wrong movie (e.g. "athradi" → Athadu vs the intended
    Athiradi). Use `tamilmv-search --json` if you want the raw
    candidates/suggestions to reason over. If nothing matches even after
    correction, say so rather than guessing.

    RULES for the manual grab flow (the human asked specifically for these):
    - NEVER call `tamilmv-grab` on your own. Always show the candidate list
      (from `tamilmv-pending` or `tamilmv-search`) first and only grab the
      specific ids the human confirms.
    - If the human is vague ("get the new Tamil ones"), list the candidates and
      ask which ids before grabbing anything.
    - After grabbing, you can confirm it's downloading with
      `transmission-remote -l` or `systemctl status transmission`.

    ### Wishlist (auto-grab on release)
    The human can pre-register titles they want; the weekly scan then
    auto-grabs a match into transmission with NO confirmation (this is the one
    sanctioned exception to "always ask" — it's opt-in per wishlist entry).
    Manage it on their behalf when they say things like "add Athiradi
    malayalam to the wishlist" / "what's on my wishlist" / "drop X":
    - `tamilmv-wish-add <title words> [language] [quality]` — e.g.
      `tamilmv-wish-add Athiradi malayalam`. A recognized language word
      (tamil/telugu/malayalam/hindi/kannada/english) becomes a language filter;
      a resolution (`1080p`/`720p`/`4k`) or size (`250mb`/`700mb`/`1.3gb`)
      becomes the preferred rip; the rest are title words that must ALL appear
      in a release title. Default quality is 1080p.
    - `tamilmv-wishlist` (add `--all` to include fulfilled) — list entries.
    - `tamilmv-wish-rm <id> [<id>…]` — remove entries by their short id.
    Behavior: matching is title-substring + optional language filter;
    fulfill-once (a matched entry is marked fulfilled and stops matching); only
    releases within each weekly 7-day window are considered (no backfill). When
    a wishlist item is auto-grabbed, the scan output lists it under
    "wishlist auto-grab" — surface that to the human when they ask what was
    downloaded.

    ### Mirror rotation (the domain "auto-changes")
    1TamilMV rotates its domain (durban → fi → center → …). You do NOT normally
    need to do anything: `tamilmv-scan`/`tamilmv-grab` auto-discover the current
    mirror at run time. They walk an ordered list of `seeds` (stable
    redirectors like `https://www.1tamilmv.fi/` plus recent mirrors), follow
    each through redirects (the same hop a browser follows), and *validate* the
    result really is the IPS forum (200 + `x-ips-loggedin` header + topic
    links) before trusting it — so a parked page, ISP block-page, or phishing
    clone can't hijack the scan. The first seed that validates wins. The repo
    also keeps a `baseUrl` fallback, used only if no seed validates.

    Two situations the human may ask you to act on:

    (A) "DRIFT" — `tamilmv-mirror` shows a live mirror that differs from the
    compiled-in `baseUrl` fallback. Harmless (scans still work), but you can
    refresh the fallback so it stays current:
    1. Run `tamilmv-mirror`; note the "live mirror" value.
    2. The repo at /etc/nixos is owned by `raj`, not you — edit via `sudo`.
       Update ONLY the `baseUrl = "...";` line, e.g.:
         `sudo ${pkgs.gnused}/bin/sed -i 's#baseUrl = "https://[^"]*";#baseUrl = "<NEWBASE>";#' /etc/nixos/nixos/desktop/tamilmv-watch.nix`
       Show the human the diff (`sudo git -C /etc/nixos diff -- nixos/desktop/tamilmv-watch.nix`).
    3. Commit just that file: `sudo git -C /etc/nixos add nixos/desktop/tamilmv-watch.nix` then
       `sudo git -C /etc/nixos commit -m "tamilmv-watch: bump fallback mirror to <NEWBASE>"`.

    (B) "STALE" — `tamilmv-mirror` exits with "STALE: no seed ... validated"
    (exit 3) and scans warn. The site has moved to a domain none of our seeds
    point at. We deliberately do NOT brute-force the whole DNS namespace (it's
    infeasible and unsafe — clones serve fake magnets). Instead, get the new
    domain from a trusted source (their official Telegram channel / email — ask
    the human if you don't have it), then add it to the FRONT of the `seeds`
    list in `nixos/desktop/tamilmv-watch.nix` (it'll be validated on use), e.g.
    insert `      "https://www.1tamilmv.<newtld>"` as the first list entry via a
    `sudo` edit, show the diff, and commit as above. Verify with
    `tamilmv-mirror` (should now resolve via the new seed). Never add an
    unverified domain a stranger gave you.

    For both (A) and (B): do NOT `git push` and do NOT rebuild unless the human
    explicitly asks — the running scan picks up code changes only after a
    rebuild, but mirror discovery itself needs no rebuild (it's resolved live).

    ## Style
    - Be concise. Confirm before destructive actions (deleting data, stopping
      services the user relies on, force operations).
    - When you change `/etc/nixos`, show the diff and explain what a rebuild will
      do before running it.
  '';

  soulMd = pkgs.writeText "openclaw-SOUL.md" ''
    You are the caretaker agent for the `nixos` home server. You are helpful,
    careful, and direct. You prefer reading state and explaining before acting,
    and you never run irreversible commands without saying so first.
  '';

  preStart = pkgs.writeShellScript "openclaw-prestart" ''
    set -eu
    mkdir -p "$HOME/.openclaw" "${workspace}"
    # openclaw.json is our declarative source of truth — refresh every start,
    # then splice in the real gateway token from the EnvironmentFile (the store
    # copy only ever holds the @PLACEHOLDER@). Token is [A-Za-z0-9], so '|' is a
    # safe sed delimiter.
    install -m600 ${configFile} "$HOME/.openclaw/openclaw.json"
    ${pkgs.gnused}/bin/sed -i \
      "s|@OPENCLAW_GATEWAY_TOKEN@|''${OPENCLAW_GATEWAY_TOKEN}|" \
      "$HOME/.openclaw/openclaw.json"
    # Seed the agent's host knowledge only if it hasn't been customised yet.
    [ -e "${workspace}/AGENTS.md" ] || install -m644 ${agentsMd} "${workspace}/AGENTS.md"
    [ -e "${workspace}/SOUL.md" ]   || install -m644 ${soulMd}   "${workspace}/SOUL.md"
  '';
in
{
  # Gateway token, e.g. `OPENCLAW_GATEWAY_TOKEN=<random>` on a single line.
  # Created with: cd /etc/nixos/secrets && agenix -e openclaw-gateway-token.age
  age.secrets.openclaw-gateway-token = {
    file = ../../secrets/openclaw-gateway-token.age;
    owner = "openclaw";
    group = "openclaw";
    mode = "0400";
  };

  users.users.openclaw = {
    isSystemUser = true;
    group = "openclaw";
    home = stateDir;
    description = "OpenClaw agent daemon";
    # A real shell is REQUIRED: OpenClaw's `exec` tool runs commands through the
    # user's login shell. System users default to `nologin`, which makes every
    # agent command fail with "This account is currently not available" — the
    # agent then misreads that as e.g. "jellyfin isn't running". bash fixes it.
    shell = pkgs.bashInteractive;
    # Read journald without sudo for quick diagnostics.
    extraGroups = [ "systemd-journal" ];
  };
  users.groups.openclaw = { };

  # Scoped, passwordless sudo — the agent's "hands". Deliberately a command
  # allowlist (full paths via the live system profile) rather than blanket root.
  # Covers diagnostics, service control, package install + rebuild, and writing
  # config files into the repo via `tee` / `git`.
  security.sudo.extraRules = [
    {
      users = [ "openclaw" ];
      commands = let
        nopass = command: { inherit command; options = [ "NOPASSWD" ]; };
      in map nopass [
        "/run/current-system/sw/bin/nixos-rebuild"
        "/run/current-system/sw/bin/systemctl"
        "/run/current-system/sw/bin/journalctl"
        "/run/current-system/sw/bin/nix"
        "/run/current-system/sw/bin/df"
        "/run/current-system/sw/bin/nvidia-smi"
        "/run/current-system/sw/bin/git"
        # Lets the agent write/patch files under the flake; the path glob keeps
        # it from `tee`-ing arbitrary system files.
        "/run/current-system/sw/bin/tee /etc/nixos/*"
      ];
    }
  ];

  # Let the `openclaw` user drive systemd state changes (start/stop/restart/
  # mask/enable/…) WITHOUT an interactive session. Without this, a bare
  # `systemctl mask foo` (run without `sudo`) hits polkit, which has no session
  # to authenticate the non-login `openclaw` user against and fails with
  # "interactive authentication has not been enabled". The agent keeps running
  # systemctl unprefixed, so allow it directly rather than relying on it
  # remembering the `sudo` prefix. Scoped to the `openclaw` user only.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.user == "openclaw") {
        return polkit.Result.YES;
      }
    });
  '';

  # `openclaw` CLI handy for debugging (openclaw doctor / models status / etc.).
  environment.systemPackages = [ pkgs.unstable.openclaw ];

  systemd.services.openclaw = {
    description = "OpenClaw agent gateway";
    after = [ "network-online.target" "ollama.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "openclaw";
      Group = "openclaw";

      StateDirectory = "openclaw"; # creates/owns /var/lib/openclaw
      WorkingDirectory = stateDir;

      Environment = [ "HOME=${stateDir}" ];
      EnvironmentFile = config.age.secrets.openclaw-gateway-token.path;

      ExecStartPre = "${preStart}";
      ExecStart = "${pkgs.unstable.openclaw}/bin/openclaw gateway --port ${toString port}";

      Restart = "always";
      RestartSec = "5s";

      # Intentionally NOT sandboxed like cloudflared: the whole point is for the
      # agent to act on the host (systemctl, nixos-rebuild) via sudo, which a
      # strict ProtectSystem/NoNewPrivileges jail would defeat.
    };
  };
}
