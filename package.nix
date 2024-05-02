{ stdenv
, lib
, rustPlatform
, installShellFiles
, makeBinaryWrapper
, darwin
, nvd
, use-nom ? true
, nix-output-monitor ? null
, rev ? "dirty"
,
}:
assert use-nom -> nix-output-monitor != null; let
  runtimeDeps = [ nvd ] ++ lib.optionals use-nom [ nix-output-monitor ];
  cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
in
rustPlatform.buildRustPackage {
  pname = "nh_darwin";
  version = "${cargoToml.package.version}-${rev}";

  src = lib.fileset.toSource {
    root = ./.;
    fileset =
      lib.fileset.intersection
        (lib.fileset.fromSource (lib.sources.cleanSource ./.))
        (lib.fileset.unions [
          ./src
          ./Cargo.toml
          ./Cargo.lock
        ]);
  };

  strictDeps = true;

  nativeBuildInputs = [
    installShellFiles
    makeBinaryWrapper
  ];

  buildInputs = lib.optionals stdenv.isDarwin [ darwin.apple_sdk.frameworks.SystemConfiguration ];

  doCheck = false; # faster builds

  preFixup = ''
    mkdir completions
    $out/bin/nh_darwin completions --shell bash > completions/nh_darwin.bash
    $out/bin/nh_darwin completions --shell zsh > completions/nh_darwin.zsh
    $out/bin/nh_darwin completions --shell fish > completions/nh_darwin.fish

    installShellCompletion completions/*
  '';

  postFixup = ''
    wrapProgram $out/bin/nh_darwin \
      --prefix PATH : ${lib.makeBinPath runtimeDeps}
  '';

  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Yet another nix cli helper. Works on NixOS, NixDarwin, and HomeManager Standalone";
    homepage = "https://github.com/ToyVo/nh_darwin";
    license = lib.licenses.eupl12;
    mainProgram = "nh_darwin";
    maintainers = with lib.maintainers; [ drupol viperML ToyVo ];
  };
}
