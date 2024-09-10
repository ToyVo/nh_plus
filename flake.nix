{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      devshell,
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
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

      perSystem =
        { pkgs, config, ... }:
        {
          overlayAttrs = {
            inherit (config.packages) nh;
          };

          formatter = pkgs.nixfmt-rfc-style;

          packages = rec {
            nh = pkgs.callPackage ./package.nix {
              rev = self.shortRev or self.dirtyShortRev or "dirty";
            };
            default = nh;
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
