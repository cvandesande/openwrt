{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  name = "openwrt-dev";

  hardeningDisable = [ "format" ];

  packages = with pkgs; [
    bash
    bc
    binutils
    bzip2
    coreutils
    diffutils
    file
    findutils
    flex
    gawk
    gcc
    gettext
    git
    gnugrep
    gnumake
    gnused
    gnutar
    gzip
    ncurses
    openssl
    patch
    perl
    pkg-config
    python3
    rsync
    unzip
    util-linux
    wget
    which
    xz
    zlib
    zstd
  ];
}
