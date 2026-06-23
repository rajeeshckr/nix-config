# This file defines overlays
{inputs, ...}: {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs final.pkgs;

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
    # example = prev.example.overrideAttrs (oldAttrs: rec {
    # ...
    # });
  };

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.system;
      config = {
        allowUnfree = true;
        # OpenClaw (nixos/desktop/openclaw.nix) is flagged insecure upstream
        # because it lets an LLM run with full system access — exactly the
        # risk we deliberately mitigate (Cloudflare Access + gateway token +
        # scoped sudo). Permit it by name so the allowance survives version
        # bumps in nixpkgs-unstable.
        # NB: check-meta runs this on the raw mkDerivation attrs (pname/version),
        # where `name` isn't set yet — so match on pname first, name second.
        allowInsecurePredicate = pkg:
          (pkg.pname or (builtins.parseDrvName (pkg.name or "")).name) == "openclaw";
      };
    };
  };
}
