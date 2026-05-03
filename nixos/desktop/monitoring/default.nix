{ config, lib, pkgs, ... }:

# Prometheus + Grafana monitoring stack for the homelab.
#
# Layout:
#   ┌──────────────────────────────────────────────────────────────┐
#   │ exporters (loopback)         │  scrape source              │
#   ├──────────────────────────────┼─────────────────────────────┤
#   │ node_exporter      :9100     │  CPU / RAM / disk / systemd │
#   │ smartctl_exporter  :9633     │  SMART health & temps       │
#   │ nginx_exporter     :9113     │  stub_status                │
#   │ postgres_exporter  :9187     │  immich DB                  │
#   │ blackbox_exporter  :9115     │  HTTP probe everything      │
#   │ exportarr-sonarr   :9707     │  sonarr API                 │
#   │ exportarr-radarr   :9708     │  radarr API                 │
#   │ vllm (native)      :8000     │  /metrics                   │
#   └──────────────────────────────┴─────────────────────────────┘
#
#   Prometheus :9090 (loopback) — scrapes everything above.
#   Grafana    :3000 (LAN + nginx subdomain) — visualises Prometheus.
#
# Nothing is exposed externally except the grafana.rajeeshckr.uk vhost
# (HTTPS via the existing ACME setup in network/internet-access.nix) and
# port 3000 on LAN for direct access.
#
# First-run notes:
#   1. After `update`, browse to https://grafana.rajeeshckr.uk (or
#      http://<host>:3000) and log in as admin/admin — Grafana forces a
#      password change on first login.
#   2. The "Homelab Overview" dashboard is provisioned automatically;
#      individual *arr/exportarr panels start populating once Sonarr and
#      Radarr have run at least once (the API key is read from their
#      config.xml at exporter start).
#   3. Jellyfin's native /metrics is disabled by default. To enable it
#      later, set <EnableMetrics>true</EnableMetrics> in
#      /srv/data/jellyfin/config/network.xml, restart jellyfin, then
#      uncomment the jellyfin scrape job below. Until then we fall back
#      to a blackbox probe (just up/down + latency).

let
  # Port choices avoid existing collisions on this host:
  #   :3000 → spliteasy-webclient   ⇒ Grafana on :3001
  #   :9090 → spliteasy-backend     ⇒ Prometheus on :9095
  #   :9091 → transmission rpc
  #   :9117 → jackett
  ports = {
    grafana       = 3001;
    prometheus    = 9095;
    node          = 9100;
    nginxExporter = 9113;
    blackbox      = 9115;
    postgres      = 9187;
    smartctl      = 9633;
    sonarrExp     = 9707;
    radarrExp     = 9708;
  };

  # Fish the API key out of the *arr config file at exporter start.
  # Avoids the agenix dance — keys live in service state dirs already.
  arrApiKeyFrom = configPath: ''
    API_KEY="$(${pkgs.gnugrep}/bin/grep -oP '(?<=<ApiKey>)[^<]+' ${configPath} || true)"
    if [ -z "$API_KEY" ]; then
      echo "exportarr: could not read API key from ${configPath} — service may not have started yet"
      sleep 30
      exit 1
    fi
  '';
in
{
  # --- Grafana ----------------------------------------------------------
  services.grafana = {
    enable = true;
    settings = {
      server = {
        domain = "grafana.rajeeshckr.uk";
        root_url = "https://grafana.rajeeshckr.uk/";
        # Bind on all interfaces so LAN clients can hit http://nixos:3000
        # without DNS. nginx still terminates TLS on the public subdomain.
        http_addr = "0.0.0.0";
        http_port = ports.grafana;
      };
      security = {
        # Cookies served via HTTPS proxy must be marked Secure to be sent
        # back from modern browsers when accessing the public subdomain.
        cookie_secure = true;
      };
      analytics.reporting_enabled = false;
    };

    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          uid = "prometheus";
          url = "http://127.0.0.1:${toString ports.prometheus}";
          isDefault = true;
          jsonData.timeInterval = "15s";
        }
      ];
      dashboards.settings.providers = [
        {
          name = "Homelab";
          options.path = ./dashboards;
          options.foldersFromFilesStructure = false;
          disableDeletion = false;
          allowUiUpdates = true;
        }
      ];
    };
  };

  # nginx vhost for Grafana — same pattern as immich/vault/jellyfin.
  services.nginx.virtualHosts."grafana.rajeeshckr.uk" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString ports.grafana}";
      proxyWebsockets = true; # live tail / explore needs WS
      extraConfig = ''
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host  $host;
      '';
    };
  };

  # --- Prometheus exporters --------------------------------------------
  services.prometheus.exporters.node = {
    enable = true;
    port = ports.node;
    enabledCollectors = [
      "systemd"
      "processes"
      "ethtool"
    ];
    extraFlags = [
      # Track per-mountpoint utilisation for /, /srv/data and the
      # mergerfs branches under /media-disk*.
      "--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|run|var/lib/docker)($|/)"
    ];
  };

  services.prometheus.exporters.smartctl = {
    enable = true;
    port = ports.smartctl;
  };

  services.prometheus.exporters.nginx = {
    enable = true;
    port = ports.nginxExporter;
    scrapeUri = "http://127.0.0.1/nginx_status";
  };

  # postgres_exporter connects via local peer auth; runAsLocalSuperUser
  # uses the `postgres` system user which immich's services.postgresql
  # already provisions. dataSourceName is required by the option even
  # when running as superuser; it's ignored at runtime.
  services.prometheus.exporters.postgres = {
    enable = true;
    port = ports.postgres;
    runAsLocalSuperUser = true;
    dataSourceName = "user=postgres host=/run/postgresql sslmode=disable";
  };

  services.prometheus.exporters.blackbox = {
    enable = true;
    port = ports.blackbox;
    configFile = (pkgs.formats.yaml {}).generate "blackbox.yml" {
      modules = {
        http_2xx = {
          prober = "http";
          timeout = "10s";
          http = {
            valid_http_versions = [ "HTTP/1.1" "HTTP/2.0" ];
            # Most homelab UIs return 200/302 to "/", but transmission's
            # RPC endpoint returns 409 to a plain GET (CSRF guard) and
            # vaultwarden/immich's API roots may 401 — accept all of those
            # as "the service is alive" for the purpose of probing.
            valid_status_codes = [ 200 301 302 401 403 404 409 ];
            method = "GET";
            follow_redirects = true;
            preferred_ip_protocol = "ip4";
          };
        };
      };
    };
  };

  # nginx_exporter needs an unrestricted stub_status endpoint on loopback.
  services.nginx.statusPage = true;

  # --- Exportarr (Sonarr / Radarr) -------------------------------------
  # Self-bootstrapping: read API key from each app's config.xml at start.
  systemd.services.exportarr-sonarr = {
    description = "Prometheus exporter for Sonarr";
    after = [ "network.target" "sonarr.service" ];
    wants = [ "sonarr.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.gnugrep ];
    script = ''
      ${arrApiKeyFrom "/srv/data/sonarr/config.xml"}
      export API_KEY
      exec ${pkgs.exportarr}/bin/exportarr sonarr \
        --url http://127.0.0.1:8989 \
        --port ${toString ports.sonarrExp}
    '';
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = "30s";
      # /srv/data/sonarr is mode 0700 owned by sonarr — easiest way to
      # read its config.xml is to just *be* the sonarr user.
      User = "sonarr";
      Group = "sonarr";
      ProtectSystem = "strict";
      PrivateTmp = true;
    };
  };

  systemd.services.exportarr-radarr = {
    description = "Prometheus exporter for Radarr";
    after = [ "network.target" "radarr.service" ];
    wants = [ "radarr.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.gnugrep ];
    script = ''
      ${arrApiKeyFrom "/srv/data/radarr/config.xml"}
      export API_KEY
      exec ${pkgs.exportarr}/bin/exportarr radarr \
        --url http://127.0.0.1:7878 \
        --port ${toString ports.radarrExp}
    '';
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "radarr";
      Group = "radarr";
      ProtectSystem = "strict";
      PrivateTmp = true;
    };
  };

  # --- Prometheus ------------------------------------------------------
  services.prometheus = {
    enable = true;
    port = ports.prometheus;
    listenAddress = "127.0.0.1";
    retentionTime = "30d";
    globalConfig.scrape_interval = "15s";

    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [
          { targets = [ "127.0.0.1:${toString ports.prometheus}" ];
            labels.instance = "nixos"; }
        ];
      }
      {
        job_name = "node";
        static_configs = [
          { targets = [ "127.0.0.1:${toString ports.node}" ];
            labels.instance = "nixos"; }
        ];
      }
      {
        job_name = "smartctl";
        scrape_interval = "5m";
        static_configs = [
          { targets = [ "127.0.0.1:${toString ports.smartctl}" ];
            labels.instance = "nixos"; }
        ];
      }
      {
        job_name = "nginx";
        static_configs = [
          { targets = [ "127.0.0.1:${toString ports.nginxExporter}" ];
            labels.instance = "nixos"; }
        ];
      }
      {
        job_name = "postgres";
        static_configs = [
          { targets = [ "127.0.0.1:${toString ports.postgres}" ];
            labels.instance = "nixos"; }
        ];
      }
      {
        job_name = "vllm";
        scrape_interval = "30s";
        metrics_path = "/metrics";
        static_configs = [
          { targets = [ "127.0.0.1:8000" ];
            labels.instance = "nixos";
            labels.model = "Hermes-3-Llama-3.2-3B"; }
        ];
      }
      {
        job_name = "exportarr-sonarr";
        scrape_interval = "60s";
        static_configs = [
          { targets = [ "127.0.0.1:${toString ports.sonarrExp}" ];
            labels.instance = "nixos"; }
        ];
      }
      {
        job_name = "exportarr-radarr";
        scrape_interval = "60s";
        static_configs = [
          { targets = [ "127.0.0.1:${toString ports.radarrExp}" ];
            labels.instance = "nixos"; }
        ];
      }
      # Blackbox HTTP probes for everything that doesn't have a native
      # /metrics endpoint we can use. Each target gets `instance="<url>"`
      # so panels can group/filter by service URL.
      {
        job_name = "blackbox";
        scrape_interval = "30s";
        metrics_path = "/probe";
        params.module = [ "http_2xx" ];
        static_configs = [
          {
            targets = [
              "http://127.0.0.1:8096"  # jellyfin
              "http://127.0.0.1:7878"  # radarr
              "http://127.0.0.1:8989"  # sonarr
              "http://127.0.0.1:6767"  # bazarr
              "http://127.0.0.1:9117"  # jackett
              "http://127.0.0.1:8191"  # flaresolverr
              "http://127.0.0.1:9091/transmission/web/" # transmission
              "http://127.0.0.1:2283"  # immich
              "http://127.0.0.1:8222"  # vaultwarden
              "http://127.0.0.1:8000/health"  # vllm
            ];
          }
        ];
        relabel_configs = [
          { source_labels = [ "__address__" ]; target_label = "__param_target"; }
          { source_labels = [ "__param_target" ]; target_label = "instance"; }
          { target_label = "__address__";
            replacement = "127.0.0.1:${toString ports.blackbox}"; }
        ];
      }
      # Jellyfin native /metrics — uncomment after enabling
      # <EnableMetrics>true</EnableMetrics> in network.xml.
      # {
      #   job_name = "jellyfin";
      #   scrape_interval = "30s";
      #   metrics_path = "/metrics";
      #   static_configs = [
      #     { targets = [ "127.0.0.1:8096" ]; labels.instance = "nixos"; }
      #   ];
      # }
    ];

    rules = [
      (builtins.toJSON {
        groups = [
          {
            name = "system";
            rules = [
              {
                alert = "HighCpuUsage";
                expr = ''100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90'';
                for = "10m";
                labels.severity = "warning";
                annotations.summary = "CPU >90% for 10m on {{ $labels.instance }}";
              }
              {
                alert = "HighMemoryUsage";
                expr = ''100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 90'';
                for = "5m";
                labels.severity = "warning";
                annotations.summary = "Memory >90% on {{ $labels.instance }}";
              }
              {
                alert = "HostDown";
                expr = "up == 0";
                for = "2m";
                labels.severity = "critical";
                annotations.summary = "Target {{ $labels.job }} ({{ $labels.instance }}) is down";
              }
            ];
          }
          {
            name = "filesystem";
            rules = [
              {
                alert = "DiskSpaceLow";
                expr = ''(node_filesystem_avail_bytes{fstype=~"ext4|xfs|zfs|btrfs|fuse.mergerfs"} / node_filesystem_size_bytes) * 100 < 10'';
                for = "10m";
                labels.severity = "warning";
                annotations.summary = "<10% free on {{ $labels.mountpoint }}";
              }
              {
                alert = "DiskSpaceCritical";
                expr = ''(node_filesystem_avail_bytes{fstype=~"ext4|xfs|zfs|btrfs|fuse.mergerfs"} / node_filesystem_size_bytes) * 100 < 5'';
                for = "2m";
                labels.severity = "critical";
                annotations.summary = "<5% free on {{ $labels.mountpoint }}";
              }
            ];
          }
          {
            name = "disk-health";
            rules = [
              {
                alert = "SmartUnhealthy";
                expr = "smartctl_device_smart_healthy == 0";
                for = "0m";
                labels.severity = "critical";
                annotations.summary = "SMART says {{ $labels.device }} ({{ $labels.model_name }}) is unhealthy";
              }
              {
                alert = "DiskTempHigh";
                expr = ''smartctl_device_temperature{temperature_type="current"} > 55'';
                for = "10m";
                labels.severity = "warning";
                annotations.summary = "{{ $labels.device }} at {{ $value }}°C";
              }
            ];
          }
          {
            name = "services";
            rules = [
              {
                alert = "ServiceDown";
                expr = ''probe_success{job="blackbox"} == 0'';
                for = "5m";
                labels.severity = "critical";
                annotations.summary = "Service probe failing: {{ $labels.instance }}";
              }
              {
                alert = "SystemdUnitFailed";
                expr = ''node_systemd_unit_state{state="failed"} == 1'';
                for = "5m";
                labels.severity = "warning";
                annotations.summary = "systemd unit failed: {{ $labels.name }}";
              }
            ];
          }
        ];
      })
    ];
  };

  # --- Firewall --------------------------------------------------------
  # Open Grafana on LAN so http://nixos:3000 works without DNS.
  # Prometheus + every exporter stay loopback-only (their default).
  networking.firewall.allowedTCPPorts = [ ports.grafana ];
}
