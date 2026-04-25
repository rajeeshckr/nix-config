# Repository Guide

This repo is the NixOS configuration for the desktop/server host **`nixos`**
(hostname is literally `nixos`). It is a flake-based config that also pulls in
`home-manager`, `agenix`, and `nixos-hardware`.

It lives at `/etc/nixos` and is a git repo — the flake reads files from the
git tree, so **new or moved files must be `git add`-ed before they're visible
to `nixos-rebuild` / `nix eval`**.

## Rebuild

The system has a shell alias defined in `nixos/config/common/default.nix`:

```sh
update   # = sudo nixos-rebuild switch --flake .#nixos
```

Run it from the repo root (`/etc/nixos`). For trickier debugging:

```sh
sudo nixos-rebuild switch --flake .#nixos --show-trace
sudo nixos-rebuild test   --flake .#nixos      # apply without making it the boot default
sudo nixos-rebuild build  --flake .#nixos      # eval + build, no activation
nix flake update                               # bump all inputs in flake.lock
nix fmt                                        # format with alejandra
```

Eval a single option without rebuilding (handy when adding a new module):

```sh
nix eval .#nixosConfigurations.nixos.config.services.<name>.<option>
```

## Top-level layout

```
/etc/nixos
├── flake.nix              # inputs (nixpkgs 24.11, unstable, home-manager, agenix, nixos-hardware) + nixosConfigurations.nixos
├── flake.lock
├── nixos/                 # NixOS system modules
│   ├── configuration.nix  # base: overlays, nix settings, agenix, openssh, timezone
│   ├── config/            # shared configuration fragments (imported by host configs)
│   │   ├── common/        # users, shell aliases (incl. `update`), basic CLI tooling
│   │   ├── graphical/     # fonts, GNOME-adjacent bits
│   │   ├── network/       # networking, internet-access controls (see INTERNET-ACCESS-SETUP.md)
│   │   ├── home-manager.nix
│   │   ├── nvidia.nix     # NVIDIA driver pin (currently 580.95.05, open kernel module)
│   │   └── llm.nix
│   └── desktop/           # the actual host config for `nixos`
│       ├── configuration.nix      # entrypoint, imports everything below + hardware-configuration.nix
│       ├── hardware-configuration.nix
│       ├── media.nix              # Jellyfin, Radarr, Sonarr, Bazarr, Jackett, FlareSolverr
│       ├── immich.nix             # Immich photo backup (services.immich)
│       ├── transmission.nix
│       ├── samba.nix
│       ├── swe-bench.nix          # SWE-bench harness w/ vLLM
│       ├── spliteasy.nix          # SplitEasy expense splitter backend
│       ├── vllm.nix
│       └── scripts/
├── home-manager/          # home-manager configs (common.nix, linux.nix, config/)
├── modules/
│   ├── nixos/             # reusable NixOS modules (exported via flake.nixosModules)
│   └── home-manager/      # reusable HM modules (exported via flake.homeManagerModules)
├── overlays/              # additions / modifications / unstable-packages overlays
├── pkgs/                  # custom packages (exported via flake.packages.<system>)
├── secrets/               # agenix-encrypted secrets (.age) + secrets.nix
├── ssh_pubkeys/
├── doc/                   # ad-hoc notes
└── README.md              # mostly ruby/direnv snippets, not the canonical guide
```

### How a rebuild assembles itself

`flake.nix` exposes `nixosConfigurations.nixos`, built from two modules:

1. `nixos/configuration.nix` — base/global config (overlays, nix settings, agenix, openssh).
2. `nixos/desktop/configuration.nix` — the host-specific config; imports everything in `nixos/config/*` and the per-service files under `nixos/desktop/`.

So **adding a new system service = create `nixos/desktop/<service>.nix` and add it to the `imports` list in `nixos/desktop/configuration.nix`**. (See `immich.nix` for a recent example.)

## Conventions

- **Service data dirs** live under `/srv/data/<service>` on the SSD root fs
  (e.g. `/srv/data/jellyfin`, `/srv/data/radarr`, `/srv/data/immich`). Postgres
  and other databases also live on `/`. Never put DB data on `/media` (mergerfs)
  or `/media-usb` — they're nearly full HDDs/USB.
- **Bulk media** lives under `/media`, which is a `fuse.mergerfs` union over
  `/media-disk1` (sdb2), `/media-disk2` (sdc1) and `/media-usb` (sda1). Mount
  options enforce `category.create=mfs` (most-free-space) and `minfreespace=1G`.
- **Stable vs unstable packages**: `pkgs.unstable.<foo>` pulls from
  `nixpkgs-unstable` via the `unstable-packages` overlay. Used selectively for
  Jellyfin/Radarr/Jackett/Lutris/shadps4 to track upstream more aggressively.
- **Unfree packages** are allowed (`nixpkgs.config.allowUnfree = true`).
- **Secrets**: encrypted with agenix; identity is `/root/.ssh/id_rsa`. Add new
  secrets via `secrets/secrets.nix` and `agenix -e <name>.age` from `secrets/`.
- **Formatting**: `nix fmt` runs `alejandra`. Existing files are not all
  formatted; don't reformat unrelated code in a single change.
- **Comments**: explain *why*, not *what*. Avoid restating what the code does.

## Hardware notes

- NVIDIA proprietary driver pinned in `nixos/config/nvidia.nix` to a specific
  version + sha256 set. Bumping requires regenerating all five hashes (see the
  commented-out alternate version in that file as a template).
- GDM forced to **Xorg** (`gdm.wayland = false`) to dodge Wayland/NVIDIA bugs.
- Auto-suspend is disabled both in GDM and via a polkit rule (this box is a
  server-ish workstation that must stay up).
- ZFS hostId is set (`networking.hostId = "cc74da59"`) but no ZFS pools are
  currently mounted; the storage pool is mergerfs over ext4.

## Network / firewall

- `media.nix` opens UDP `1900, 7359, 9091, 9117, 7878` and TCP `8191`.
- `transmission.nix`, `samba.nix`, `swe-bench.nix`, `spliteasy.nix`, `immich.nix`
  each open their own ports via `openFirewall = true` or explicit
  `networking.firewall.allowed*Ports`. When adding a service, prefer the
  module's `openFirewall` option over hand-rolled firewall rules.
- Tailscale is installed (binary in `systemPackages`) but not enabled as a
  service here — it's managed manually if at all.

## After a rebuild — sanity checks

```sh
systemctl --failed
journalctl -u <service> -e --no-pager
df -h /                   # /srv/data/* lives here, watch for fill-up
nvidia-smi                # confirm the driver loaded
```

## Things that are easy to get wrong

1. Forgetting to `git add` a new `.nix` file → flake eval fails with
   `path '/nix/store/.../<file>.nix' does not exist`.
2. Editing `/etc/nixos` outside the repo (it *is* the repo, but a stray
   `configuration.nix` at `/etc/nixos/configuration.nix` would be ignored — the
   real entrypoints are under `nixos/`).
3. Touching `nixos/config/nvidia.nix` without updating all five hashes; the
   build will fail with a hash mismatch.
4. Putting service state on `/media` — mergerfs + `minfreespace=1G` will start
   refusing writes once a branch is full, and Immich/Postgres explicitly
   require a Unix-permission-aware local FS.
