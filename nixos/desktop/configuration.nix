# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ inputs, pkgs, ... }:

{
  imports =
    [
      ../config/zfs.nix
      ../config/nvidia-patch.nix
      ../config/home-manager.nix
      ../config/llm.nix
      ../config/common.nix
      ../config/nfs_mounts.nix
      ./hardware-configuration.nix
    ];

  networking.hostName = "desktop"; # Define your hostname.
  networking.hostId = "cc74da59";

  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  networking.firewall.enable = false;

  services.syncthing.settings.devices."laptop" = { id = "S5V7OMM-KMCFGTF-DI2X72J-QNY565R-XBWZERU-MH6LCDV-QLTSNYJ-FKJ47A2"; };

  programs.wireshark.enable = true;

  services.avahi = {
    enable = true;
    reflector = true;
    allowInterfaces = ["tailscale0" "enp4s0" ];
    allowPointToPoint = true;
  };


  # Enable the X11 windowing system.
  services.xserver.videoDrivers = ["nvidia"];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # core
    vim
    firefox
    
    # social
    mumble
    element
    gnupg

    # dev
    wireshark
    wineWowPackages.stable
    winetricks

    # fun
    unstable.lutris
    unstable.shadps4
    r2modman

    # misc
    calibre
  ];



  # bluetooth
  services.blueman.enable = true;
  hardware.bluetooth.enable = true; # enables support for Bluetooth
  hardware.bluetooth.powerOnBoot = true; # powers up the default Bluetooth controller on boot

  # steam
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
 #   localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
  };

  # open source NVIDIA game streaming service
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
    
  };

  # VR streaming
  programs.alvr = {
    enable = true;
    openFirewall = true;
  };

  services.smartd = {
    enable = true;
  };

  nixpkgs.overlays = [inputs.nvidia-patch.overlays.default];

  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}

