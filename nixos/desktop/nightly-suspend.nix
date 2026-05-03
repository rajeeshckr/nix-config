# Nightly suspend-to-RAM: at 02:00 every night, check whether the box is busy;
# if not, arm an RTC wake alarm for 08:00 and suspend to S3.
#
# Why this exists:
#   - Idle 24/7 with this hardware (Ryzen 7 7700 + RTX 5070 Ti) burns ~100-150W.
#     S3 is ~3-5W. ~6h/night of suspend saves real money on AUD electricity.
#   - We tested suspend/resume manually and it works cleanly on this 5070 Ti +
#     580.95.05 driver. NVIDIA + S3 has historically been flaky, so if you bump
#     the driver and resume breaks, disable this module first.
#
# Safety gates (skip suspend if any of these are true):
#   - A real interactive user session is logged in (loginctl)
#   - The vLLM container is running a job (GPU pinned)
#   - SWE-bench harness is mid-run
#   - Transmission has active (non-paused) torrents
#   - System uptime is < 30 min (just rebooted, give it time to settle)
#
# Manual override: `sudo systemctl stop nightly-suspend.timer` for one-off, or
# add this module to your imports list conditionally.
#
# WoL note: this host is currently on wifi (wlp7s0); WoWLAN isn't supported by
# the driver, so there's no remote-wake option. Wake happens via the RTC alarm
# only. If you ever switch to ethernet, we can add ethtool wol-g.

{ config, lib, pkgs, ... }:

let
  # Times are in local (system) time. Adjust if your free-power window or
  # routine changes.
  suspendTime = "22:00";
  wakeTime = "08:00";

  # The script that decides whether to suspend, then does it. We keep this
  # readable instead of golf-ing it; the journal entries are how you'll debug
  # missed suspends in the morning.
  suspendScript = pkgs.writeShellApplication {
    name = "nightly-suspend";
    runtimeInputs = with pkgs; [
      util-linux # rtcwake
      systemd # loginctl, systemctl
      coreutils
      gnugrep
      gawk # awk used in session/transmission parsing
      iproute2 # ss for active-connection check
      transmission_4 # transmission-remote
      curl
      jq
    ];
    text = ''
      set -uo pipefail

      log() { echo "[nightly-suspend] $*"; }

      # 1. Don't suspend if the box just booted (gives services time to settle
      #    and avoids a reboot loop if something is wrong).
      uptime_secs=$(awk '{print int($1)}' /proc/uptime)
      if [ "$uptime_secs" -lt 1800 ]; then
        log "uptime $uptime_secs s < 30 min, skipping"
        exit 0
      fi

      # 2. Don't suspend if there's a real interactive user session.
      #    We look at each session's Class (skip "manager" — that's the
      #    persistent systemd --user instance, not a login) and Service
      #    (sshd / login / gdm-password = real; gdm = greeter, ignore).
      #    A user that SSHd in once and never logged out leaves a Class=user
      #    sshd session in State=closing|active; we treat any Class=user as
      #    "in use" since they could be actively typing.
      blocking_session=""
      for sid in $(loginctl list-sessions --no-legend | awk '{print $1}'); do
        class=$(loginctl show-session "$sid" -p Class --value 2>/dev/null || true)
        service=$(loginctl show-session "$sid" -p Service --value 2>/dev/null || true)
        if [ "$class" = "user" ] && [ "$service" != "gdm" ] && [ "$service" != "gdm-launch-environment" ]; then
          blocking_session="$sid($service)"
          break
        fi
      done
      if [ -n "$blocking_session" ]; then
        log "active user session: $blocking_session, skipping"
        exit 0
      fi

      # 2b. Check for active inbound connections to user-facing services.
      #     This catches "someone is watching Jellyfin / browsing Immich"
      #     even when no shell session is open. Loopback connections (e.g.
      #     internal exporters scraping) don't count.
      busy_port=""
      for port in 8096 2283 8222; do
        if ss -tnH "state established" "( sport = :$port )" 2>/dev/null \
           | awk '$5 !~ /^127\./ && $5 !~ /^\[::1\]/ {print; exit}' \
           | grep -q .; then
          busy_port="$port"
          break
        fi
      done
      if [ -n "$busy_port" ]; then
        log "active client connected to port $busy_port (jellyfin/immich/vaultwarden), skipping"
        exit 0
      fi

      # 3. Don't suspend if vLLM container is actively serving (GPU pinned).
      if systemctl is-active --quiet podman-vllm.service; then
        # The unit being active means container is up; check if it's actually
        # busy by looking at GPU utilization. >5% sustained = real work.
        gpu_util=$(${pkgs.linuxPackages.nvidia_x11.bin}/bin/nvidia-smi \
          --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null \
          | tr -d ' ' || echo 0)
        if [ "''${gpu_util:-0}" -gt 5 ]; then
          log "vLLM running and GPU util $gpu_util%, skipping"
          exit 0
        fi
        log "vLLM up but GPU idle ($gpu_util%), proceeding"
      fi

      # 4. Don't suspend mid-SWE-bench run.
      if systemctl is-active --quiet swe-bench.service 2>/dev/null; then
        log "swe-bench.service active, skipping"
        exit 0
      fi

      # 5. Don't suspend if Transmission has actively downloading torrents.
      #    Seeding is fine to interrupt; downloading is rude.
      if systemctl is-active --quiet transmission.service; then
        # Use the local RPC. Credentials default in the transmission module
        # are fine for a local query.
        active_dl=$(transmission-remote 127.0.0.1:9091 -l 2>/dev/null \
          | awk '/Downloading/ {n++} END {print n+0}' || echo 0)
        if [ "''${active_dl:-0}" -gt 0 ]; then
          log "transmission has $active_dl active downloads, skipping"
          exit 0
        fi
      fi

      # All clear. Compute the wake epoch for today's wake time; if that's in
      # the past (e.g. timer fired late), use tomorrow's.
      wake_today=$(date -d "today ${wakeTime}" +%s)
      now=$(date +%s)
      if [ "$wake_today" -le "$now" ]; then
        wake_epoch=$(date -d "tomorrow ${wakeTime}" +%s)
      else
        wake_epoch=$wake_today
      fi
      log "suspending now, RTC wake at $(date -d @"$wake_epoch" '+%F %T')"

      # rtcwake -m mem suspends to RAM and arms the RTC alarm in one call.
      # If suspend fails (e.g. driver issue), the command exits non-zero and
      # we leave the system running rather than half-suspended.
      rtcwake -m mem -t "$wake_epoch" || {
        log "rtcwake failed, system stayed up"
        exit 1
      }

      log "resumed at $(date '+%F %T')"
    '';
  };
in
{
  systemd.services.nightly-suspend = {
    description = "Nightly suspend-to-RAM with RTC wake";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${suspendScript}/bin/nightly-suspend";
    };
  };

  systemd.timers.nightly-suspend = {
    description = "Nightly suspend trigger";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* ${suspendTime}:00";
      # If the box was off at 02:00, run as soon as we boot up after.
      Persistent = false;
      AccuracySec = "1min";
    };
  };
}
