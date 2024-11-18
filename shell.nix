{pkgs ? import <nixpkgs> {}}:
with pkgs;
  mkShell {
    strictDeps = true;

    nativeBuildInputs = [
      cargo
      rustc

      rust-analyzer-unwrapped
      rustfmt
      clippy
      nvd
      nix-output-monitor
      taplo
      yaml-language-server
    ];

    buildInputs = [];

    env = {
      NH_NOM = "1";
      RUST_LOG = "nh=trace";
      RUST_SRC_PATH = "${rustPlatform.rustLibSrc}";
    };
  }
