{
  description = "nh_darwin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    crate2nix.url = "github:nix-community/crate2nix";
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-trusted-public-keys = "eigenvalue.cachix.org-1:ykerQDDa55PGxU25CETy9wF6uVDpadGGXYrFNJA3TUs=";
    extra-substituters = "https://eigenvalue.cachix.org";
    allow-import-from-derivation = true;
  };

  outputs =
    inputs @ { self
    , nixpkgs
    , flake-parts
    , crate2nix
    , devshell
    }: flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports = [
        flake-parts.flakeModules.easyOverlay
        devshell.flakeModule
        ./devshell.nix
      ];

      perSystem = { pkgs, config, ... }: {
        overlayAttrs = {
          inherit (config.packages) nh_darwin;
        };
        packages = rec {
          nh_darwin = pkgs.callPackage ./package.nix {
            inherit crate2nix;
            rev = self.shortRev or self.dirtyShortRev or "dirty";
          };
          default = nh_darwin;
        };
      };

      flake = {
        nixosModules.default = import ./module.nix self;
        # use this module before this pr is merged https://github.com/LnL7/nix-darwin/pull/942
        nixDarwinModules.prebuiltin = import ./darwin-module.nix self;
        # use this module after that pr is merged
        nixDarwinModules.default = import ./module.nix self;
        # use this module before this pr is merged https://github.com/nix-community/home-manager/pull/5304
        homeManagerModules.prebuiltin = import ./home-manager-module.nix self;
        # use this module after that pr is merged
        homeManagerModules.default = import ./module.nix self;
      };
    };
}
