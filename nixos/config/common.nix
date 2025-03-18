{ pkgs, ... }:

{
  # enable zsh integration with nix
  programs.zsh = {
    enable = true;
  };
}