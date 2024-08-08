# Make sure I can test builds on linux from macos
FROM nixos/nix
RUN mkdir /src
WORKDIR /src
ADD . ./
RUN nix --extra-experimental-features "nix-command flakes" build .#nh_darwin --accept-flake-config
CMD ["./result/bin/nh_darwin"]
