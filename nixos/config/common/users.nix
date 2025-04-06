{ pkgs, ... }:

{
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
