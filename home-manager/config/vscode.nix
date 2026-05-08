{ pkgs, ... }: {
  # home-manager 25.05+ moved per-profile vscode settings under
  # `programs.vscode.profiles.<name>.*` so users with multiple VS Code
  # profiles can configure each. We only have one profile, so use `default`.
  programs.vscode = {
    enable = true;
    profiles.default.extensions = with pkgs.vscode-extensions; [
        # core
        dracula-theme.theme-dracula
        vscodevim.vim

        # golang
        golang.go

        # rust
        rust-lang.rust-analyzer

        # ruby
        shopify.ruby-lsp

        # nix
        jnoortheen.nix-ide

        # terraform
        hashicorp.hcl

        # system
        timonwong.shellcheck
        coolbear.systemd-unit-file

        # openscad
        antyos.openscad

        # extras
        signageos.signageos-vscode-sops
        ms-vscode-remote.remote-ssh
        github.copilot
        github.copilot-chat
        ms-vscode.makefile-tools

        # remote ssh
        ms-vscode-remote.remote-ssh-edit
        ms-vscode-remote.remote-ssh        
    ];
  };
}
