self: { pkgs, ... }: {
  programs.nh.package = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
}
