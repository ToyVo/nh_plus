{ inputs, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      devshells.default = {
        imports = [
          "${inputs.devshell}/extra/language/c.nix"
          # "${devshell}/extra/language/rust.nix"
        ];

        commands = with pkgs; [
          {
            package = cargo;
            category = "rust";
          }
        ];

        packages =
          with pkgs;
          [
            cargo
            rustc
            rust-analyzer-unwrapped
            rustfmt
            clippy
            nvd
            nix-output-monitor
          ]
          ++ lib.optionals stdenv.isDarwin [ darwin.apple_sdk.frameworks.SystemConfiguration ];

        env = [
          {
            name = "NH_NOM";
            value = "1";
          }
          {
            name = "RUST_LOG";
            value = "nh=trace";
          }
          {
            name = "RUST_SRC_PATH";
            value = "${pkgs.rustPlatform.rustLibSrc}";
          }
        ];

        language.c = {
          libraries = lib.optional pkgs.stdenv.isDarwin pkgs.libiconv;
        };
      };
    };
}
