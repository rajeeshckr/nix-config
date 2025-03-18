{ pkgs, ... }:

{
  imports =
    [
      ./users.nix
      ./zfs.nix
    ];

  # enable zsh integration with nix
  programs.zsh = {
    enable = true;
  };
}