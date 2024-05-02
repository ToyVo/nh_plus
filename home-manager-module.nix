# Notice: this file will only exist until this pr is merged https://github.com/nix-community/home-manager/pull/5304
self: { config, lib, pkgs, ... }:

let cfg = config.programs.nh;
in {
  meta.maintainers = with lib.maintainers; [ johnrtitor ];

  options.programs.nh = {
    enable = lib.mkEnableOption "nh_darwin, yet another Nix CLI helper. Works on NixOS, NixDarwin, and HomeManager Standalone";

    package = lib.mkPackageOption pkgs "nh" { } // {
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
    };

    flake = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        The path that will be used for the `FLAKE` environment variable.

        `FLAKE` is used by nh_darwin as the default flake for performing actions, like `nh_darwin os switch`.
      '';
    };
  };

  config = {
    assertions = [{
      assertion = (cfg.flake != null) -> !(lib.hasSuffix ".nix" cfg.flake);
      message = "nh.flake must be a directory, not a nix file";
    }];

    home = lib.mkIf cfg.enable {
      packages = [ cfg.package ];
      sessionVariables = lib.mkIf (cfg.flake != null) { FLAKE = cfg.flake; };
    };
  };
}
