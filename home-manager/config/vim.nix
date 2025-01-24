{ pkgs, ... }: {
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
    plugins = with pkgs.vimPlugins; [
        leap-nvim
        vim-nix
        vim-go
        vim-ruby
        vim-startify
    ];
  };
}
