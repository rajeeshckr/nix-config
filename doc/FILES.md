# Files Documentation

Below is an overview of the NixOS configuration files in this repository.

---

## nixos/configuration.nix
This file defines your primary NixOS system configuration.  
• Imports other modules, including ./config/users.nix.  
• Configures system-wide settings such as the boot loader, time zone, networking, and environment packages.  
• Includes overlays for extending or modifying packages (under nixpkgs.overlays).  
• Manages Nix settings like experimental features and registry.  

---

## nixos/config/users.nix
This file defines user accounts and their settings.  
• Declares user groups.  
• Sets authorised SSH keys.  
• Configures user privileges by assigning extraGroups.  

---

## modules/nixos/default.nix
This file is intended for reusable NixOS modules you might share or reuse.  
• You can import individual files from here (like ./my-module.nix).  
• Useful for organising custom NixOS functionality into separate modules.  

---

Feel free to expand this documentation as your configuration grows.
