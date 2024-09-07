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
, crate2nix
, callPackage
, buildRustCrate
, defaultCrateOverrides
}:
assert use-nom -> nix-output-monitor != null; let
  runtimeDeps = [ nvd ] ++ lib.optionals use-nom [ nix-output-monitor ];
  cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
  generated = crate2nix.tools.${stdenv.hostPlatform.system}.generatedCargoNix {
    name = "nh_darwin";
    src = ./.;
  };
  crates = callPackage "${generated}/default.nix" {
    buildRustCrateForPkgs = _: buildRustCrate.override {
      defaultCrateOverrides = defaultCrateOverrides // {
        nh_darwin = attrs: {
          version = "${cargoToml.package.version}-${rev}";
          nativeBuildInputs = [
            installShellFiles
            makeBinaryWrapper
          ];

          buildInputs = lib.optionals stdenv.isDarwin [ darwin.apple_sdk.frameworks.SystemConfiguration ];

          postInstall =
            ''
              wrapProgram $out/bin/nh_darwin \
                --prefix PATH : ${lib.makeBinPath runtimeDeps}
            ''
            +
              lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) # sh
                ''
                  installShellCompletion --cmd nh_darwin \
                    --bash <("$out/bin/nh_darwin" completions --shell bash) \
                    --zsh <("$out/bin/nh_darwin" completions --shell zsh) \
                    --fish <("$out/bin/nh_darwin" completions --shell fish)
                '';

          meta = {
            description = "Yet another nix cli helper. Works on NixOS, NixDarwin, and HomeManager Standalone";
            homepage = "https://github.com/ToyVo/nh_darwin";
            license = lib.licenses.eupl12;
            mainProgram = "nh_darwin";
            maintainers = with lib.maintainers; [ drupol viperML ToyVo ];
          };
        };
      };
    };
  };
in
crates.rootCrate.build
