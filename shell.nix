{ pkgs ? import <nixpkgs> {}
, extraPkgs ? []
}:

let
  fixWrapper = pkgs.runCommand "fix-wrapper" {} ''
    mkdir -p $out/bin
    for i in ${pkgs.gcc.cc}/bin/*-gnu-gcc*; do
      ln -s ${pkgs.gcc}/bin/gcc $out/bin/$(basename "$i")
    done
    for i in ${pkgs.gcc.cc}/bin/*-gnu-{g++,c++}*; do
      ln -s ${pkgs.gcc}/bin/g++ $out/bin/$(basename "$i")
    done
    ln -sf ${pkgs.gcc.cc}/bin/{,*-gnu-}gcc-{ar,nm,ranlib} $out/bin
  '';

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
      fixWrapper
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
