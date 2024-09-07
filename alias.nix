{
  nh_darwin,
  runCommand,
  lib,
  stdenv,
  installShellFiles,
}:
runCommand "${nh_darwin.name}-alias" { nativeBuildInputs = [ installShellFiles ]; } (
  ''
    mkdir -p "$out/bin"
    ln -s ${lib.escapeShellArg (lib.getExe nh_darwin)} "$out/bin/nh"
  ''
  +
    lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) # sh
      ''
        installShellCompletion --cmd nh \
          --bash <("$out/bin/nh" completions --shell bash) \
          --zsh <("$out/bin/nh" completions --shell zsh) \
          --fish <("$out/bin/nh" completions --shell fish)
      ''
)
