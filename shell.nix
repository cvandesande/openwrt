{ pkgs ? import <nixpkgs> {}
, extraPkgs ? []
}:

let
  fhs = pkgs.buildFHSEnv {
    name = "openwrt-env";
    runScript = "bash";
    targetPkgs = pkgs: with pkgs; [
      bash
      bc
      bison
      bzip2
      ccache
      coreutils
      diffutils
      file
      findutils
      flex
      gawk
      gcc
      gettext
      git
      glibc.static
      gnumake
      gnugrep
      gnused
      gnutar
      gzip
      ncurses
      openssl
      patch
      perl
      pkg-config
      (python3.withPackages (ps: [ ps.setuptools ]))
      rsync
      subversion
      swig
      unzip
      util-linux
      wget
      which
      xz
      libxcrypt
      zlib
      zlib.static
      zstd
    ] ++ extraPkgs;
    multiPkgs = null;
    extraOutputsToInstall = [ "dev" ];
    profile = ''
      export hardeningDisable=all
      export NIX_HARDENING_ENABLE=
      export NIX_HARDENING_ENABLE_x86_64_unknown_linux_gnu=
      export AR=gcc-ar
      export NM=gcc-nm
      export RANLIB=gcc-ranlib
      export FAKEROOTDONTTRYCHOWN=1
    '';
  };
in pkgs.mkShell {
  name = "openwrt-env-wrapper";
  packages = [ fhs ];
  shellHook = ''
    exec ${fhs}/bin/openwrt-env
  '';
}
