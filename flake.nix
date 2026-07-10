{
  description = "OpenWrt FHS build environment (NixOS)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # gcc's cross-prefixed binutils wrappers (e.g. x86_64-unknown-linux-gnu-gcc-ar)
      # aren't symlinked under their unprefixed names on PATH by default; some
      # host tool builds (e.g. zstd) invoke $AR/$NM/$RANLIB as plain gcc-ar/gcc-nm/
      # gcc-ranlib, so provide those names explicitly.
      fixWrapper = pkgs.runCommand "fix-wrapper" { } ''
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
        ];
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
    in {
      # Non-interactive/scripted use: nix run . -- -c 'make -j$(nproc) target/linux/compile'
      packages.${system}.default = fhs;
      apps.${system}.default = {
        type = "app";
        program = "${fhs}/bin/openwrt-env";
      };

      # Interactive use: nix develop
      devShells.${system}.default = pkgs.mkShell {
        name = "openwrt-env-wrapper";
        packages = [ fhs ];
        shellHook = ''
          exec ${fhs}/bin/openwrt-env
        '';
      };
    };
}
