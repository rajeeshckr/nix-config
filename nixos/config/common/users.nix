{ pkgs, ... }:

{
  # Allow wheel group to sudo without password
  security.sudo.wheelNeedsPassword = false;

  users.groups.raj = {};
  users.users = {
    raj = {
      group = "raj";
      shell = pkgs.zsh;
      extraGroups = [ "wireshark" "wheel" "docker" ]; # Enable ‘sudo’ for the user.
      isNormalUser = true;     
    };
  };
}
