# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ inputs, pkgs, ... }:

{
  imports =
    [
      ../config/graphical
      ../config/common
      ../config/network
      ../config/home-manager.nix
      ../config/nvidia.nix
      ../config/llm.nix
      ./hardware-configuration.nix
      ./transmission.nix
      ./media.nix 
      ./samba.nix
      ./swe-bench.nix  # SWE-bench AI coding benchmarks with vLLM
      ./spliteasy.nix  # SplitEasy expense splitting backend
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  # Using default kernel for better NVIDIA driver compatibility.
  # If you need to pin, prefer the default kernel:
  # boot.kernelPackages = pkgs.linuxPackages;

  networking.hostName = "nixos"; # Define your hostname.
  networking.hostId = "cc74da59";

  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  programs.wireshark.enable = true;
  programs.nix-ld.enable = true;

  # --- Storage Pool Setup --------------------------------------------------
  # Goal: Users keep using /media while data is transparently distributed
  # across two physical disks (former /dev/sda2 + new SSD partition).
  # Strategy: Mount each disk at a hidden/aux path then present a union
  # view at /media using mergerfs (non-destructive, keeps existing data).

  # Underlying first disk (existing data previously at /media)
  fileSystems."/media-disk1" = {
    device = "/dev/disk/by-uuid/f1bf15ac-ae5c-4c75-89dc-1b7030be6a46";
    fsType = "ext4";
    options = [ "defaults" "noatime" ];
  };

  # Underlying second disk (make sure it's formatted & labeled: mkfs.ext4 -L MEDIA2 /dev/sdb1)
  fileSystems."/media-disk2" = {
    device = "/dev/disk/by-label/MEDIA2";
    fsType = "ext4";
    options = [ "defaults" "noatime" ];
  };

  # Unified pool presented at /media
  # mergerfs concatenates directories; new files placed according to policy.
  # category.create=mfs => choose drive with most free space for new creates.
  fileSystems."/media" = {
    device = "/media-disk1:/media-disk2";
    fsType = "fuse.mergerfs";
    options = [
      "defaults"
      "allow_other"
      "use_ino"
      "category.create=mfs"
      "moveonenospc=true"
      "cache.files=partial"
      "dropcacheonclose=true"
      "fsname=mergerfs"
    ];
  };

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
    glances

    # fun
    unstable.lutris
    unstable.shadps4
    r2modman

    # misc
    calibre

    # networking and security
    ddclient
    tailscale
    mkcert
    certbot

    nixfmt-rfc-style

    pkgs.authentik

    pciutils # Provides lspci
    usbutils # Provides lsusb

    thefuck
    mergerfs # required for the fuse.mergerfs pooled /media mount
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
    localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
  };

  # enable docker support
  virtualisation.docker = {
    enable = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.raj = {
    isNormalUser = true;
    description = "raj";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
    #  thunderbird
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMX7Ty1TvVNqSlBFRuyt3dAfCIaRxRke1eG28/YAA4GL rajeesh.ckr@gmail.com"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDZNeEOWfDR8Rk6gLlOh0bT4BBIu0HmjXpBQWRb76rHfTZc5AKrHF5u1xqSbWltNcNtJ5yUg/JCKTx4RQMHfA5lX5S9jRsGQKIWmghz0DM6ElO2yXiQ9DkPdD4YHIUq/Y2VjH9lzYTLrZhZEosxxzQPfIAF0pXCZqTd/4O+nGoX0dV5KjXXXYa5HWJ0mLginy0yahFO9dfJBg0K27vDLeij8WNVuENZGChy3j5303qiuEHe23OxnsiIsZZ2TA6kfpOcL20s4HzDcAfMzlf6gX3Nk8I5db5jJwE4hKwbzHvxhfvoJSSBtdmRgTmW0htvMSmEckP5t7pWsIuQDWfk/d7xvBLvXhc0kxWDQ+QsKzDPSbqLszTTFFpGwtMApoV7sPjZOW7iLw1HH/Fd7uZ94EbHXq/qmBaxRugz0ChbucwnfdXAQcG9CsZFHZ0kBvz1BKdAQqLb4coS0J2mzpUcUcFedzlZKbD0pxEVOF4EeUm2mcGTKBE4I5ZcmCiS9TNlNMB0XjhWLZw/9tORfULtkKQ/2h5b82tPCmNfhn+pmtncooJSWgVb5E+e96ii2QyJApWSK+7Wci34gNnuPChR3tQ6VMiKhX7SpK+NsT9OKIisgha3CVAenwISrcVoerSgAzExTmh9ysRHl1FlPUYYBrJ3a/EMkNYCIoN3EGv1Rrg8PQ== rajeesh.ckr@gmail.com"
    ];
  };


  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;


  # disable auto suspend
  services.xserver.displayManager.gdm.autoSuspend = false;
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.login1.suspend" ||
            action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
            action.id == "org.freedesktop.login1.hibernate" ||
            action.id == "org.freedesktop.login1.hibernate-multiple-sessions")
        {
            return polkit.Result.NO;
        }
    });
  '';

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # nixpkgs.overlays = [inputs.nvidia-patch.overlays.default];

  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
