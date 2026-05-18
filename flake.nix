{
  description = "blar: BLAR archive format and tool, built on BLIP";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        zig = zig-overlay.packages.${system}."0.16.0";
        pname = "blar";
        version = "3.0.0";
        isDarwin = pkgs.stdenv.isDarwin;

        zigDepsHash = "sha256-l1P5b7/M6qCIVxHeOnNXL7cyx9ZIEWXG/Mh2IklJVpo=";

        zigDeps = pkgs.stdenv.mkDerivation {
          pname = "${pname}-zig-deps";
          inherit version;
          src = self;
          nativeBuildInputs = with pkgs; [ zig git cacert ];
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = zigDepsHash;
          dontPatchShebangs = true;
          buildPhase = ''
            export HOME=$TMPDIR
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
            mkdir -p $ZIG_GLOBAL_CACHE_DIR
            export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            export GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            zig build --fetch=all
          '';
          installPhase = ''
            mkdir -p $out
            cp -r $TMPDIR/zig-cache/p $out/p
          '';
          dontFixup = true;
        };
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            zig
            hyperfine
            libjxl
            zlib
          ];
          shellHook = ''
            export JXL_INCLUDE_PATH="${pkgs.libjxl.dev}/include"
            export JXL_LIB_PATH="${pkgs.libjxl}/lib"
          '';
        };

        packages.default = pkgs.stdenv.mkDerivation {
          inherit pname version;
          src = self;
          nativeBuildInputs = [ zig ]
            ++ pkgs.lib.optionals isDarwin [
              pkgs.darwin.cctools
              pkgs.apple-sdk
            ];
          buildInputs = [ pkgs.libjxl pkgs.zlib ];
          dontConfigure = true;
          dontInstall = true;
          dontFixup = true;
          buildPhase = ''
            export HOME="$TMPDIR"
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
            mkdir -p $ZIG_GLOBAL_CACHE_DIR
            cp -r ${zigDeps}/* $ZIG_GLOBAL_CACHE_DIR/
            chmod -R u+w $ZIG_GLOBAL_CACHE_DIR
            zig build --prefix $out -Doptimize=ReleaseFast \
              -Djxl-include-path=${pkgs.libjxl.dev}/include \
              -Djxl-lib-path=${pkgs.libjxl}/lib \
              -Dzlib-lib-path=${pkgs.zlib}/lib
          '';
        };

        checks.default = pkgs.stdenv.mkDerivation {
          pname = "${pname}-tests";
          inherit version;
          src = self;
          nativeBuildInputs = [ zig ]
            ++ pkgs.lib.optionals isDarwin [
              pkgs.darwin.cctools
              pkgs.apple-sdk
            ];
          buildInputs = [ pkgs.libjxl pkgs.zlib ];
          dontConfigure = true;
          dontFixup = true;
          buildPhase = ''
            export HOME="$TMPDIR"
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
            mkdir -p $ZIG_GLOBAL_CACHE_DIR
            cp -r ${zigDeps}/* $ZIG_GLOBAL_CACHE_DIR/
            chmod -R u+w $ZIG_GLOBAL_CACHE_DIR
            ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
              # Find the glibc dynamic linker for this architecture so
              # test binaries (linking libjxl -> libc) can be exec'd in
              # the Nix build sandbox.
              GLIBC_LD=$(echo ${pkgs.glibc.out}/lib/ld-linux-*.so.*)
              EXTRA_FLAGS="-Ddynamic-linker=$GLIBC_LD"
            ''}
            timeout 600 zig build test \
              -Djxl-include-path=${pkgs.libjxl.dev}/include \
              -Djxl-lib-path=${pkgs.libjxl}/lib \
              -Dzlib-lib-path=${pkgs.zlib}/lib \
              ''${EXTRA_FLAGS:-} \
              || { echo "Tests failed"; exit 1; }
          '';
          installPhase = ''
            mkdir -p $out
            echo "tests passed" > $out/result
          '';
        };
      }
    );
}
