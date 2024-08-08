self: { config, pkgs, lib, ... }:
{
  config = {
    nixpkgs.overlays = [ self.overlays.default ];
    programs.nh.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
}
