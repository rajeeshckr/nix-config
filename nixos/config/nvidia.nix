{ config, ... }:
{
  nixpkgs.config = {
    nvidia.acceptLicense = true;
  };

  boot.blacklistedKernelModules = [ "nouveau" ];

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
      open = false;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.beta;

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
