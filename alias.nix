{
  nh_darwin,
  runCommand,
  lib,
}:
runCommand "${nh_darwin.name}-alias" { } ''
  mkdir -p "$out/bin"
  ln -s ${lib.escapeShellArg (lib.getExe nh_darwin)} "$out/bin/nh"
''
