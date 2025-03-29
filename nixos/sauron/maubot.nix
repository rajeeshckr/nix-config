{ config
, lib
, ... }:
let cfg = config.server;
in {
  age = {
    secrets = {
      maubot-secret-config = {
        file = ../../secrets/maubot-secret-config.age;
        owner = "maubot";
        group = "maubot";
      };
    };
  };
  services.maubot = {
    enable = true;
    dataDir = "/srv/data/maubot";
    extraConfigFile = config.age.secrets.maubot-secret-config.path;
    settings = {
      database = "sqlite:/srv/data/maubot/maubot.db";
    };
    plugins = with config.services.maubot.package.plugins; [
      chatgpt
    ];
  };
  nixpkgs.config.permittedInsecurePackages = [
    "olm-3.2.16"
  ];
}