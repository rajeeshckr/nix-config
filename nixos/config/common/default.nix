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
    enableCompletions = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
        enable = true;
        plugins = [ "git" "thefuck" ];
        theme = "robbyrussell";
      };
      
    shellAliases = {
      ll = "ls -l";
      update = "sudo nixos-rebuild switch --flake .#nixos";
    };
    history.size = 10000;
  };

  services.smartd = {
    enable = true;
  };
}
