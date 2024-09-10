# Notice: this file will only exist until this pr is merged https://github.com/nix-community/home-manager/pull/5304
self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.nh;
  nh_darwin = self.packages.${pkgs.stdenv.hostPlatform.system}.nh_darwin;
  nh = pkgs.callPackage ./alias.nix { nh_darwin = cfg.package; };
in
{
  meta.maintainers = with lib.maintainers; [ johnrtitor ];

  options.programs.nh = {
    enable = lib.mkEnableOption "nh_darwin, yet another Nix CLI helper. Works on NixOS, NixDarwin, and HomeManager Standalone";

    package = lib.mkPackageOption pkgs "nh" { } // {
      default = nh_darwin;
    };

    alias = lib.mkEnableOption "Enable alias of nh_darwin to nh";

    flake = {
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
  };

  config = {
    assertions = [
      {
        assertion = (cfg.flake.os != null) -> !(lib.hasSuffix ".nix" cfg.flake.os);
        message = "nh.flake.os must be a directory, not a nix file";
      }
      {
        assertion = (cfg.flake.home != null) -> !(lib.hasSuffix ".nix" cfg.flake.home);
        message = "nh.flake.home must be a directory, not a nix file";
      }
    ];

    home = lib.mkIf cfg.enable {
      packages = [ cfg.package ] ++ lib.optionals (cfg.alias) [ nh ];
      sessionVariables = lib.mkMerge [
        (lib.mkIf (cfg.flake.os != null) { NH_OS_FLAKE = cfg.flake.os; })
        (lib.mkIf (cfg.flake.home != null) { NH_HOME_FLAKE = cfg.flake.home; })
      ];
    };
  };
}
