# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  # You can import other home-manager modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    # ./firefox.nix # get working on darwin
  ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages

      # You can also add overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
    };
  };

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    extraConfig = ''
      set number

      set tabstop     =4
      set softtabstop =4
      set shiftwidth  =4
      set expandtab

    '';
  };

  home = {
    username = "sam";
    homeDirectory = "/home/sam";
  };

  programs.zsh = {
    enable = true;
    initExtra = ''
      autoload -z edit-command-line
      zle -N edit-command-line
      bindkey "^X^E" edit-command-line
    '';
    shellAliases = {
      gst = "git status";
      k = "kubectl";
      kgp = "kubectl get pods";
      glog = "git log -S";
    };
  };

  home.file = {
    Docker.source = config.lib.file.mkOutOfStoreSymlink "${pkgs.podman}/bin/podman";
    Docker.target = "${config.home.homeDirectory}/.local/bin/docker";
  };

  home.packages = with pkgs; [
    jq
    git
    gh
    yq
    kubectl
    kubectx
    ripgrep
    keepassxc
    podman
    qemu
    jsonnet
    stern
    fzf
  ];

  # Enable home-manager and git
  programs.home-manager.enable = true;
  programs.git.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
