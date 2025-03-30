{ config
, lib
, pkgs
, ... }:
let cfg = config.server;
in {
  services.open-webui = {
    enable = true;
    openFirewall = true;
    port = 11111;
    environment = {
      OLLAMA_API_BASE_URL = "http://desktop:11434";
    };
  };

  services.nginx.virtualHosts."open-webui.middleearth.samlockart.com" = {
    forceSSL = false;
    enableACME = false;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.open-webui.port}";
      recommendedProxySettings = true;
    };
  };
}