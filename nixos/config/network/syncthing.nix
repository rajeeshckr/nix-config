{ pkgs, ... }:

{
  services.syncthing = {
    enable = true;
    user = "sam";
    dataDir = "/home/sam/vault";    # Default folder for new synced folders
    configDir = "/home/sam/.config/syncthing";   # Folder for Syncthing's settings and keys
    openDefaultPorts = true;
    guiAddress = "http://127.0.0.1:8384";
  };
}