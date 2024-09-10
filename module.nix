self:
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.programs.nh;
  nh_darwin = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
  nh = pkgs.callPackage ./alias.nix { nh_darwin = cfg.package; };
in
{
  options.programs.nh.alias = lib.mkEnableOption "Enable alias of nh_darwin to nh";
  options.programs.nh.flake = {
    os = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        The path that will be used for the `NH_OS_FLAKE` environment variable.

        `NH_OS_FLAKE` is used by nh_darwin as the default flake for performing actions on NixOS/nix-darwin, like `nh_darwin os switch`.
      '';
    };
    home = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        The path that will be used for the `NH_HOME_FLAKE` environment variable.

        `NH_HOME_FLAKE` is used by nh_darwin as the default flake for performing actions on home-manager, like `nh_darwin home switch`.
      '';
    };
  };
  config = {
    nixpkgs.overlays = [ self.overlays.default ];
    programs.nh.package = lib.mkDefault nh_darwin;
    environment.systemPackages = lib.mkIf (cfg.enable && cfg.alias) [
      nh
    ];
    environment.variables = lib.mkMerge [
      (lib.mkIf (cfg.flake.os != null) { NH_OS_FLAKE = cfg.flake.os; })
      (lib.mkIf (cfg.flake.home != null) { NH_HOME_FLAKE = cfg.flake.home; })
    ];
  };
}
