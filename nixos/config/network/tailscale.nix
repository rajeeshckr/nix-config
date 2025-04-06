{ pkgs, ... }:

{
  # enable zsh integration with nix
  programs.zsh = {
    enable = true;
  };

  # tailscale
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };
}
