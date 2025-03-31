{ config
, lib
, pkgs
, ... }:
let cfg = config.server;
in {

  services.grafana = {
    enable = true;
    settings = {
        server = {
          domain = "grafana.middleearth.samlockart.com";
          root_url = "http://${toString config.services.grafana.settings.server.domain}/";
          protocol = "http";
          http_port = 3000;
          http_addr = "127.0.0.1";
          serve_from_sub_path = false;
        };
    };
  };

  services.nginx.virtualHosts.${toString config.services.grafana.settings.server.domain} = {
    forceSSL = false;
    enableACME = false;
    locations."/" = {
      proxyPass = "${toString config.services.grafana.settings.server.protocol}://${toString config.services.grafana.settings.server.http_addr}:${toString config.services.grafana.settings.server.http_port}";
      recommendedProxySettings = true;
      proxyWebsockets = true;
    };
  };

  # https://nixos.org/manual/nixos/stable/#module-services-prometheus-exporters
  services.prometheus.exporters.node = {
    enable = true;
    port = 9000;
    # https://github.com/NixOS/nixpkgs/blob/nixos-24.05/nixos/modules/services/monitoring/prometheus/exporters.nix
    enabledCollectors = [ "systemd" ];
    # /nix/store/zgsw0yx18v10xa58psanfabmg95nl2bb-node_exporter-1.8.1/bin/node_exporter  --help
    extraFlags = [ "--collector.ethtool" "--collector.softirqs" "--collector.tcpstat" ];
  };

  services.prometheus.exporters = {
    zfs.enable = true;
    nginx.enable = true;
  };

  services.prometheus = {
    enable = true;
    globalConfig.scrape_interval = "10s";
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{
          targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ];
        }];
      }

      {
        job_name = "zfs";
        static_configs = [{
          targets = [ "localhost:${toString config.services.prometheus.exporters.zfs.port}" ];
        }];
      }

      {
        job_name = "nginx";
        static_configs = [{
          targets = [ "localhost:${toString config.services.prometheus.exporters.nginx.port}" ];
        }];
      }
    ];
  }; 
}