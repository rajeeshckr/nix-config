{ pkgs, ... }:

{
  imports =
    [
      ./users.nix
    ];

  # enable zsh integration with nix
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;

    ohMyZsh = {
        enable = true;
        plugins = [ "git" "thefuck" ];
        theme = "jonathan";
      };
      
    shellAliases = {
      ll = "ls -l";
      update = "sudo nixos-rebuild switch --flake .#nixos";
    };
  };

  services.smartd = {
    enable = true;
  };
}
