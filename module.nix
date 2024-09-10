self:
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.programs.nh;
in
{
  options.programs.nh.flake = {
    os = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        The path that will be used for the `NH_OS_FLAKE` environment variable.

        `NH_OS_FLAKE` is used by nh as the default flake for performing actions on NixOS/nix-darwin, like `nh os switch`.
      '';
    };
    home = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        The path that will be used for the `NH_HOME_FLAKE` environment variable.

        `NH_HOME_FLAKE` is used by nh as the default flake for performing actions on home-manager, like `nh home switch`.
      '';
    };
  };
  config = {
    nixpkgs.overlays = [ self.overlays.default ];
    programs.nh.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.default;
    environment.variables = lib.mkMerge [
      (lib.mkIf (cfg.flake.os != null) { NH_OS_FLAKE = cfg.flake.os; })
      (lib.mkIf (cfg.flake.home != null) { NH_HOME_FLAKE = cfg.flake.home; })
    ];
  };
}
