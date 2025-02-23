{ pkgs }:
# https://lazamar.co.uk/nix-versions/?package=ghidra&version=11.1.2&fullName=ghidra-11.1.2&keyName=ghidra&revision=ab7b6889ae9d484eed2876868209e33eb262511d&channel=nixpkgs-unstable#instructions
let
  oldPkgs = import (builtins.fetchGit {
    name = "old-revision";
    url = "https://github.com/NixOS/nixpkgs/";
    ref = "refs/heads/nixpkgs-unstable";
    rev = "ab7b6889ae9d484eed2876868209e33eb262511d"; # 11.1.2
  }) {};
in
oldPkgs.ghidra