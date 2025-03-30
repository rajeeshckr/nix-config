{ config
, lib
, pkgs
, ... }:
let cfg = config.server;
in {
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };
  programs.msmtp = {
    enable = true;
    setSendmail = true;
    defaults = {
      aliases = "/etc/aliases";
      port = 465;
      tls_trust_file = "/etc/ssl/certs/ca-certificates.crt";
      tls = true;
      auth = "login";
      tls_starttls = "off";
    };
    accounts = {
      default = {
        host = "smtp.sendgrid.com";
	tls_fingerprint = "3F:C8:AD:FE:3F:20:7F:D9:90:F4:9D:56:14:64:DE:97:A4:64:F7:3B:2F:AE:FD:0D:74:94:22:CF:A2:F5:A8:01";
        passwordeval = "cat /srv/data/secrets/sendgrid";
        user = "apikey";
        from = "sauron@samlockart.com";
      };
    };
  };
  environment.etc = {
    "aliases" = {
      text = ''
	root: sam@samlockart.com
      '';
	mode = "0644";
    };
  };
}