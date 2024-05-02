{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  };

  outputs =
    { self
    , nixpkgs
    ,
    }:
    let
      forAllSystems = function:
        nixpkgs.lib.genAttrs [
          "x86_64-linux"
          "aarch64-linux"
          # experimental
          "x86_64-darwin"
          "aarch64-darwin"
        ]
          (system: function nixpkgs.legacyPackages.${system});

      rev = self.shortRev or self.dirtyShortRev or "dirty";
    in
    {
      overlays.default = final: prev: {
        nh = self.packages.${final.stdenv.system}.nh;
      };

      packages = forAllSystems (pkgs: rec {
        nh = pkgs.callPackage ./package.nix {
          inherit rev;
        };
        default = nh;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.callPackage ./devshell.nix { };
      });

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
}
