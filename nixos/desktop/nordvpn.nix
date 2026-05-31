{ pkgs, lib, config, ... }:

# NordVPN — commercial VPN for privacy (WireGuard via NordLynx).
#
# After rebuild:
#   nordvpn login            # opens browser for OAuth
#   nordvpn set technology nordlynx
#   nordvpn set killswitch on
#   nordvpn connect
#
# Cloudflare Tunnel compatibility:
#   The allowlist below ensures cloudflared can always reach Cloudflare's
#   edge even when the kill switch is active or the VPN reconnects.

let
  nordvpn = pkgs.callPackage ../../pkgs/nordvpn { };
in
{
  environment.systemPackages = [ nordvpn ];

  users.groups.nordvpn = { };
  users.users.raj.extraGroups = [ "nordvpn" ];

  # NordVPN needs reverse path filtering relaxed for its tunnel routing.
  # "loose" satisfies both NordVPN and Tailscale (which also needs it).
  networking.firewall.checkReversePath = lib.mkForce "loose";

  # NordVPN requires systemd-resolved to set DNS on the VPN interface.
  services.resolved.enable = true;
  networking.networkmanager.dns = "systemd-resolved";

  # NordVPN daemon uses ports 443/tcp (control) and 1194/udp (OpenVPN fallback).
  # NordLynx (WireGuard) uses a dynamic UDP port that the daemon handles.
  networking.firewall.allowedTCPPorts = [ 443 ];
  networking.firewall.allowedUDPPorts = [ 1194 ];

  systemd.services.nordvpnd = {
    description = "NordVPN daemon";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      HOME = "/root";
      LD_LIBRARY_PATH = "/usr/lib64/nordvpn:/usr/lib/nordvpn";
    };
    serviceConfig = {
      ExecStartPre = pkgs.writeShellScript "nordvpn-init" ''
        mkdir -m 700 -p /var/lib/nordvpn
        if [ -z "$(ls -A /var/lib/nordvpn)" ]; then
          cp -r ${nordvpn}/var/lib/nordvpn/* /var/lib/nordvpn || true
        fi
      '';
      ExecStart = "${nordvpn}/bin/nordvpnd";
      NonBlocking = true;
      KillMode = "process";
      Restart = "on-failure";
      RestartSec = 5;
      RuntimeDirectory = "nordvpn";
      RuntimeDirectoryMode = "0750";
      Group = "nordvpn";
    };
  };

  # Allowlist Cloudflare Tunnel anycast IPs so cloudflared bypasses the VPN.
  # This keeps the tunnel alive regardless of NordVPN connection state.
  systemd.services.nordvpn-cloudflare-allowlist = {
    description = "Allowlist Cloudflare Tunnel IPs in NordVPN";
    after = [ "nordvpnd.service" ];
    wants = [ "nordvpnd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ nordvpn ];
    script = ''
      sleep 3
      # Cloudflare Tunnel (Argo) anycast ranges
      nordvpn allowlist add subnet 198.41.192.0/24 || true
      nordvpn allowlist add subnet 198.41.200.0/24 || true
      # Localhost — needed for nginx ↔ backends communication
      nordvpn allowlist add subnet 127.0.0.0/8 || true
      # LAN — so local devices can still reach services directly
      nordvpn allowlist add subnet 192.168.1.0/24 || true
    '';
  };

  # Tailscale IP range — allow direct Tailscale connectivity while VPN is on
  systemd.services.nordvpn-tailscale-allowlist = {
    description = "Allowlist Tailscale IP range in NordVPN";
    after = [ "nordvpnd.service" ];
    wants = [ "nordvpnd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ nordvpn ];
    script = ''
      sleep 3
      nordvpn allowlist add subnet 100.64.0.0/10 || true
    '';
  };
}
