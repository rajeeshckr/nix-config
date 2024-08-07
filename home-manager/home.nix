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

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
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
    plugins = [
        {
            plugin = pkgs.vimPlugins.vim-sneak;
            config = "let g:sneak#label = 1";
        }
    ];
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
      gco = "git checkout";
      k = "kubectl";
      kgp = "kubectl get pods";
      glog = "git log -S";
    };
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
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
    unstable.go
    kustomize
    direnv
  ];

  # Enable home-manager and git
  programs.home-manager.enable = true;
  programs.git = {
    enable = true;
    userName = "alam0rt";
    aliases = {
      "new" = "!git checkout -b sam.lockart/$1 && :";
    };
    ignores = [
      ".idea/"
      "shell.nix"
      ".envrc"
      ".direnv/"
    ];
    extraConfig = {
      url."ssh://git@github.com/".insteadOf = "https://github.com/";
      push.autoSetupRemote = true;
    };
  };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
