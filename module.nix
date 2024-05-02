self: { pkgs, lib, ... }: {
  programs.nh.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.default;
}
