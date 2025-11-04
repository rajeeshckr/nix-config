{ config, lib, ... }:
{
  nixpkgs.config = {
    nvidia.acceptLicense = true;
  };

  boot.blacklistedKernelModules = [ "nouveau" "nvidiafb" ];

  # Helpful on very new GPUs while waiting for official support
  boot.kernelParams = [
    "nvidia.NVreg_OpenRmEnableUnsupportedGpus=1"
  ];

  # Enable OpenGL/graphics stack
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # required for Steam and other 32-bit apps
  };

  # Load NVIDIA driver
  services.xserver.videoDrivers = [ "nvidia" ];

  # Use Xorg session for GNOME to avoid Wayland/NVIDIA issues
  services.xserver.displayManager.gdm.wayland = false;

  hardware = {

    nvidia = {
      modesetting.enable = true;
      powerManagement = {
        enable = false;
        finegrained = false;
      };
      open = true;
      nvidiaSettings = true;
      nvidiaPersistenced = true;
      package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
        version = "580.95.05";
        sha256_64bit = "sha256-hJ7w746EK5gGss3p8RwTA9VPGpp2lGfk5dlhsv4Rgqc=";
        sha256_aarch64 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        openSha256 = "sha256-RFwDGQOi9jVngVONCOB5m/IYKZIeGEle7h0+0yGnBEI=";
        settingsSha256 = "sha256-F2wmUEaRrpR1Vz0TQSwVK4Fv13f3J9NJLtBe4UP2f14=";
        persistencedSha256 = "sha256-QCwxXQfG/Pa7jSTBB0xD3lsIofcerAWWAHKvWjWGQtg=";
      };

#   package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
 #    version = "570.133.07";
  #   sha256_64bit = "sha256-LUPmTFgb5e9VTemIixqpADfvbUX1QoTT2dztwI3E3CY=";
   #  sha256_aarch64 = "sha256-yTovUno/1TkakemRlNpNB91U+V04ACTMwPEhDok7jI0=";
 #    openSha256 = "sha256-9l8N83Spj0MccA8+8R1uqiXBS0Ag4JrLPjrU3TaXHnM=";
  #   settingsSha256 = "sha256-XMk+FvTlGpMquM8aE8kgYK2PIEszUZD2+Zmj2OpYrzU=";
   #  persistencedSha256 = "sha256-G1V7JtHQbfnSRfVjz/LE2fYTlh9okpCbE4dfX9oYSg8=";
  # };

#      prime = { 
#            offload = {
 #     enable = true;
  #    enableOffloadCmd = true;
   # };
        # Make sure to use the correct Bus ID values for your system!
 #       nvidiaBusId = "PCI:01:00.0";  # This is the Bus ID for your NVIDIA GPU.
  #    };
    };
  };

}
