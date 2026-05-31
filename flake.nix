{
  description = "Your new nix config";

  inputs = {
    # Nixpkgs — bumped 24.11 → 25.11 in May 2026 to satisfy authentik-nix
    # (its module uses lib.types.pathWith, added after 24.11). Bumping the
    # whole flake is cleaner than carrying a second nixpkgs just for one
    # service. system.stateVersion stays pinned at "24.11" — that gates
    # one-shot migrations and should track the install vintage, not the
    # current nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    # You can access packages and modules from different nixpkgs revs
    # at the same time. Here's an working example:
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    # Also see the 'unstable-packages' overlay at 'overlays/default.nix'.

    # Home manager — must track the same release branch as nixpkgs.
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # s3cr3ts
    agenix.url = "github:ryantm/agenix";


    # nvidia-patch
#    nvidia-patch.url = "github:icewind1991/nvidia-patch-nixos";  
 #   nvidia-patch.inputs.nixpkgs.follows = "nixpkgs";

    # hardware modules
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Authentik (SSO / IdP) — community flake providing the NixOS module,
    # outpost packages, postgres/redis wiring and a binary cache.
    # nixpkgs ships only the `authentik` package (no `services.authentik`),
    # so this flake is what makes it actually deployable.
    # IMPORTANT: do NOT set inputs.nixpkgs.follows here — upstream warns
    # that overriding the pinned nixpkgs breaks the python deps.
    authentik-nix.url = "github:nix-community/authentik-nix";

  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    agenix,
    nixos-hardware,
    ...
  } @ inputs: let
    inherit (self) outputs;
    # Supported systems for your flake packages, shell, etc.
    systems = [
      "aarch64-linux"
      "i686-linux"
      "x86_64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    # This is a function that generates an attribute by calling a function you
    # pass to it, with each system as an argument
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    # Your custom packages
    # Accessible through 'nix build', 'nix shell', etc
    packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});
    # Formatter for your nix files, available through 'nix fmt'
    # Other options beside 'alejandra' include 'nixpkgs-fmt'
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    # Your custom packages and modifications, exported as overlays
    overlays = import ./overlays {inherit inputs;};
    # Reusable nixos modules you might want to export
    # These are usually stuff you would upstream into nixpkgs
    nixosModules = import ./modules/nixos;
    # Reusable home-manager modules you might want to export
    # These are usually stuff you would upstream into home-manager
    homeManagerModules = import ./modules/home-manager;

    # NixOS configuration entrypoint
    # Available through 'nixos-rebuild --flake .#your-hostname'
    nixosConfigurations = {
      nixos = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        modules = [
          # > Our main nixos configuration file <
          ./nixos/configuration.nix
          ./nixos/desktop/configuration.nix
          inputs.authentik-nix.nixosModules.default
        ];
      };
    };
  };
}
