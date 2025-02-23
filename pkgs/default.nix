# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
pkgs: {
  # example = pkgs.callPackage ./example { };
#  ghidra-11-1-2 = pkgs.callPackage ./ghidra {}; # not currently working
#  hex010editor = pkgs.callPackage ./010editor {}; # not currently working
}
