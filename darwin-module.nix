self:{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.programs.nh;
in
{
  meta.maintainers = [ lib.maintainers.ToyVo ];

  options.programs.nh = {
    enable = lib.mkEnableOption "nh, yet another Nix CLI helper";

    package = lib.mkPackageOption pkgs "nh" { } // {
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
    };

    flake = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        The path that will be used for the `NH_FLAKE` environment variable.

        `NH_FLAKE` is used by nh as the default flake for performing actions, like `nh os switch`.
      '';
    };

    clean = {
      enable = lib.mkEnableOption "periodic garbage collection with nh clean all";

      # Not in NixOS module
      user = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "User that runs the garbage collector.";
      };

      interval = lib.mkOption {
        type = lib.types.attrs;
        default = { Weekday = 0; };
        description = ''
          How often cleanup is performed. Passed to launchd.StartCalendarInterval

          The format is described in
          {manpage}`crontab(5)`.
        '';
      };

      extraArgs = lib.mkOption {
        type = lib.types.singleLineStr;
        default = "";
        example = "--keep 5 --keep-since 3d";
        description = ''
          Options given to nh clean when the service is run automatically.

          See `nh clean all --help` for more information.
        '';
      };
    };
  };

  config = {
    warnings =
      if (!(cfg.clean.enable -> !config.nix.gc.automatic)) then [
        "programs.nh.clean.enable and nix.gc.automatic are both enabled. Please use one or the other to avoid conflict."
      ] else [ ];

    assertions = [
      # Not strictly required but probably a good assertion to have
      {
        assertion = cfg.clean.enable -> cfg.enable;
        message = "programs.nh.clean.enable requires programs.nh.enable";
      }

      {
        assertion = (cfg.flake != null) -> !(lib.hasSuffix ".nix" cfg.flake);
        message = "nh.flake must be a directory, not a nix file";
      }
    ];

    nixpkgs.overlays = [ self.overlays.default ];

    environment = lib.mkIf cfg.enable {
      systemPackages = [ cfg.package ];
      variables = lib.mkIf (cfg.flake != null) {
        NH_FLAKE = cfg.flake;
      };
    };

    launchd = lib.mkIf cfg.clean.enable {
      daemons.nh-clean = {
        command = "exec ${lib.getExe cfg.package} clean all ${cfg.clean.extraArgs}";
        environment.NIX_REMOTE = "daemon";
        serviceConfig.RunAtLoad = false;
        serviceConfig.StartCalendarInterval = [ cfg.clean.interval ];
        serviceConfig.UserName = cfg.clean.user;
      };
    };
  };
}
