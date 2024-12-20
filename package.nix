{
  stdenv,
  lib,
  rustPlatform,
  installShellFiles,
  makeBinaryWrapper,
  darwin,
  nvd,
  use-nom ? true,
  nix-output-monitor ? null,
  rev ? "dirty",
}:
assert use-nom -> nix-output-monitor != null;
let
  runtimeDeps = [ nvd ] ++ lib.optionals use-nom [ nix-output-monitor ];
  cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
in
rustPlatform.buildRustPackage {
  pname = "nh_plus";
  version = "${cargoToml.package.version}-${rev}";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.intersection (lib.fileset.fromSource (lib.sources.cleanSource ./.)) (
      lib.fileset.unions [
        ./src
        ./Cargo.toml
        ./Cargo.lock
      ]
    );
  };

  strictDeps = true;

  nativeBuildInputs = [
    installShellFiles
    makeBinaryWrapper
  ];

  buildInputs = lib.optionals stdenv.isDarwin [ darwin.apple_sdk.frameworks.SystemConfiguration ];

  doCheck = false; # faster builds

  preFixup = ''
    installShellCompletion --cmd nh \
      --bash <("$out/bin/nh" completions --shell bash) \
      --zsh <("$out/bin/nh" completions --shell zsh) \
      --fish <("$out/bin/nh" completions --shell fish)
  '';

  postFixup = ''
    wrapProgram $out/bin/nh \
      --prefix PATH : ${lib.makeBinPath runtimeDeps}
  '';

  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Fork of nh with added support for nix-darwin and other features.";
    homepage = "https://github.com/ToyVo/nh_plus";
    license = lib.licenses.eupl12;
    mainProgram = "nh";
    maintainers = with lib.maintainers; [
      ToyVo
    ];
  };
}
