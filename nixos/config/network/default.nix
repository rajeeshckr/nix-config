{ pkgs, ... }:

{
  imports =
    [
      ./tailscale.nix
      ./nfs_mounts.nix
      ./syncthing.nix
    ];

}