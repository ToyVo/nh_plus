[![dependency status](https://deps.rs/repo/github/ToyVo/nh/status.svg)](https://deps.rs/repo/github/ToyVo/nh)

<h1 align="center">nh - fork</h1>

<h6 align="center">Because the name "yet-another-<u>n</u>ix-<u>h</u>elper" was too long to type...</h1>

## Why fork?

The original owner is unwilling to pull in changes to support darwin because they don't have a mac to be able to maintain support https://github.com/viperML/nh/issues/67 & https://github.com/viperML/nh/pull/97

## What has been added?

- `nh os switch` works on nix-darwin
- nixDarwinModules.default is similar to the nixosModule for nix.gc and programs.nh.clean
- Use this fork of nh in nixDarwinModules.default and nixosModules.default

## What does it do?

NH reimplements some basic nix commands. Adding functionality on top of the existing solutions, like nixos-rebuild, home-manager cli or nix itself.

As the main features:
- Tree of builds with [nix-output-monitor](https://github.com/maralorn/nix-output-monitor)
- Visualization of the upgrade diff with [nvd](https://gitlab.com/khumba/nvd)
- Asking for confirmation before performing activation

<p align="center">
  <img
    alt="build: passing"
    src="./.github/screenshot.png"
    width="800px"
  >
</p>


## Installation

### Nixpkgs

nh is available in nixpkgs:

- https://search.nixos.org/packages?channel=unstable&query=nh
- Hydra status:
  - x86_64-linux: https://hydra.nixos.org/job/nixos/trunk-combined/nixpkgs.nh.x86_64-linux
  - aarch64-linux: https://hydra.nixos.org/job/nixos/trunk-combined/nixpkgs.nh.aarch64-linux


### NixOS module

The NixOS module has some niceties, like an alternative to `nix.gc.automatic` which also cleans XDG profiles, result and direnv GC roots.

```nix
{ config, pkgs, ... }:
{
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 4d --keep 3";
    flake = "/home/user/my-nixos-config";
  };
}
```

### FLAKE environment variable

nh uses the `FLAKE` environment variable as the default flake to use for its operations. This can be configured by whichever method you want,
or use the `programs.nh.flake` NixOS option.

### Specialisations support

nh is capable of detecting which specialisation you are running, so it runs the proper activation script.
To do so, you need to give nh some information of the spec that is currently running by writing its name to `/etc/specialisation`. The config would look like this:

```nix
{config, pkgs, ...}: {
  specialisation."foo".configuration = {
    environment.etc."specialisation".text = "foo";
    # ..rest of config
  };

  specialisation."bar".configuration = {
    environment.etc."specialisation".text = "bar";
    # ..rest of config
  };
}
```


## Hacking

Just `nix develop`. We also provide an `.envrc` for direnv.
