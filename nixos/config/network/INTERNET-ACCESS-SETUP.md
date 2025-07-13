# Internet Access Setup for Home Services

This document explains how to set up internet access to your home services using the configuration provided in `internet-access.nix`.

## Prerequisites

1. A router that allows port forwarding
2. An account with a Dynamic DNS provider (like dyndns.org, no-ip.com, etc.)
3. Stable internet connection with a public IP address (or access through CGNAT via Tailscale)

## Configuration Steps

### 1. Update Your Dynamic DNS Configuration

Edit `internet-access.nix` and update the following fields with your Dynamic DNS provider information:

```nix
services.ddclient = {
  domains = [ "your-chosen-domain.dyndns.org" ]; # Replace with your actual domain
  username = "your-username"; # Your DDNS username
  password = "your-password"; # Your DDNS password/token
  protocol = "dyndns2"; # Protocol based on your provider
  server = "members.dyndns.org"; # Server based on your provider
}
```

### 2. Configure Port Forwarding on Your Router

Forward the following ports from your router to your NixOS machine (IP: 192.168.1.29):

- TCP 80 (HTTP)
- TCP 443 (HTTPS)
- TCP 8096 (Jellyfin)
- Any other specific ports for services you want to expose

### 3. Configure Tailscale Funnel (Alternative to Port Forwarding)

After deploying the configuration, run these commands to expose services via Tailscale Funnel:

```bash
# Authenticate with Tailscale if not already authenticated
sudo tailscale up

# Enable Funnel for specific services (example: Jellyfin on port 8096)
sudo tailscale serve https / http://localhost:8096
```

This will create a public HTTPS URL that forwards to your local Jellyfin server.

### 4. Set Up HTTPS Certificates

For direct port forwarding (not using Tailscale Funnel), set up certificates:

```bash
# Option 1: Using mkcert for local development
mkcert -install
mkcert your-domain.dyndns.org

# Option 2: Using Let's Encrypt for production
sudo certbot --nginx -d your-domain.dyndns.org
```

### 5. Customizing Exposed Services

To expose different services, modify the nginx virtual hosts in `internet-access.nix`:

```nix
services.nginx = {
  virtualHosts = {
    "your-domain.dyndns.org" = {
      locations."/" = {
        proxyPass = "http://127.0.0.1:PORT"; # Replace PORT with your service port
        proxyWebsockets = true; # Enable if needed
      };
    };
    # Add more virtual hosts as needed
  };
};
```

## Security Considerations

1. Only expose services that are necessary
2. Consider setting up authentication for all exposed services
3. Keep your system and services updated regularly
4. Monitor logs for any suspicious activities

## Troubleshooting

1. Check if ports are open: `sudo ss -tulpn`
2. Verify service status: `systemctl status nginx tailscale ddclient`
3. Check firewall rules: `sudo nix-shell -p iptables --run "iptables -L"`
4. Tail logs: `journalctl -fu nginx` or `journalctl -fu tailscale`