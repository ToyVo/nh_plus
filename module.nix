self: { config, pkgs, lib, ... }:
let
  nh_darwin = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
  nh = (pkgs.runCommand "${nh_darwin.pname}-docker-compat-${nh_darwin.version}"
    {
      outputs = [ "out" ];
      inherit (nh_darwin) meta;
    } ''
    mkdir -p $out/bin
    ln -s ${nh_darwin}/bin/nh_darwin $out/bin/nh
  '');
in
{
  options.programs.nh.alias = lib.mkEnableOption "Enable alias of nh_darwin to nh";
  config = {
    nixpkgs.overlays = [ self.overlays.default ];
    programs.nh.package = lib.mkDefault nh_darwin;
    environment.systemPackages = lib.mkIf (config.programs.nh.enable && config.programs.nh.alias) [ nh ];
  };
}
