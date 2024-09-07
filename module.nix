self: { config, pkgs, lib, ... }:
let
  cfg = config.programs.nh;
  nh_darwin = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
  nh = pkgs.callPackage ./alias.nix { nh_darwin = cfg.package; };
in
{
  options.programs.nh.alias = lib.mkEnableOption "Enable alias of nh_darwin to nh";
  config = {
    nixpkgs.overlays = [ self.overlays.default ];
    programs.nh.package = lib.mkDefault nh_darwin;
    environment.systemPackages = lib.mkIf (cfg.enable && cfg.alias) [
      nh
    ];
  };
}
