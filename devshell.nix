{
  mkShell,
  nvd,
  nix-output-monitor,
  rust-bin
}:
let
  toolchain = rust-bin.stable.latest.default.override {
    extensions = [
      "rust-src" "rust-analyzer" "rustfmt" "clippy"
    ];
  };
in
mkShell  {
  strictDeps = true;

  nativeBuildInputs = [
    toolchain
    nvd
    nix-output-monitor
  ];

  buildInputs = [];

  env = {
    NH_NOM = "1";
    RUST_LOG = "nh-darwin=trace";
    RUST_SRC_PATH = "${toolchain}/lib/rustlib/src/rust/library";
  };
}
