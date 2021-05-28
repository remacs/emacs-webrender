{
  description = "emacsNg Nix flake";

  inputs = {
    nixpkgs.url = "nixpkgs/67bbabc0a471ec286cf63f3424c91eb8b31d9000";
    emacs-overlay = {
      type = "github";
      owner = "nix-community";
      repo = "emacs-overlay";
    };

    master.url = "nixpkgs/7d71001b796340b219d1bfa8552c81995017544a";
    devshell-flake.url = "github:numtide/devshell";
    emacsNg-src = { url = "github:emacs-ng/emacs-ng"; flake = false; };
    flake-compat = { url = "github:edolstra/flake-compat"; flake = false; };
    rust-overlay = { url = "github:oxalica/rust-overlay"; inputs.nixpkgs.follows = "nixpkgs"; };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, master, emacs-overlay, emacsNg-src, flake-compat, rust-overlay, flake-utils, devshell-flake }:
    { }
    //
    (flake-utils.lib.eachSystem [ "x86_64-linux" "x86_64-darwin" ]
      (system:
        let
          unstable = final: prev: {
            inherit ((import master) { inherit system; })
              rustracer;
          };
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              self.overlay
              emacs-overlay.overlay
              rust-overlay.overlay
              devshell-flake.overlay
              unstable
            ];
            config = { };
          };
        in
        rec {
          devShell = with pkgs; let
            custom-llvmPackages = llvmPackages_10;
          in
          devshell.mkShell {
            imports = [
              ./nix/rust.nix
              (devshell.importTOML ./nix/commands.toml)
            ];

            packages = [
              custom-llvmPackages.clang
            ];
            env = [
              {
                name = "LIBCLANG_PATH";
                value = "${custom-llvmPackages.libclang}/lib";
              }
              {
                name = "CACHIX_AUTH_TOKEN";
                value =
                  let
                    pwd = builtins.getEnv "PWD";
                    key = pwd + "/nix/cachix-key.secrets";
                  in
                  if lib.pathExists key then
                    lib.removeSuffix "\n" (builtins.readFile key) else "";
              }
            ];

            commands = with pkgs; [
              {
                name = "copy-deps";
                command = ''
                  cp -rf --no-preserve=mode,ownership ${emacsNg-rust}/.cargo/ $@
                '';
                help = ''
                  copy emacsNg rust deps path to where
                '';
              }
            ];
          };


          apps = {
            emacsNg = flake-utils.lib.mkApp { drv = packages.emacsNg; exePath = "/bin/emacs"; };
          };

          defaultApp = apps.emacsNg;

          defaultPackage = pkgs.emacsNg;
          packages = flake-utils.lib.flattenTree
            {
              inherit (pkgs)
                emacsNg-rust
                emacsNg
                ;
            };

          hydraJobs = {
            inherit packages;
          };
        }
      )
    )
    // {
      overlay = final: prev:
        let
          emacsNgSource = emacsNg-src;
          #emacsNgSource = ./.;
          #rust nightly date
          locked-date = prev.lib.removePrefix "nightly-" (prev.lib.removeSuffix "\n" (builtins.readFile ./rust-toolchain));
        in
        {
          emacsNg-rust = with final;
            (
              let
                installPhase = ''
                  tar --owner=0 --group=0 --numeric-owner --format=gnu \
                      --sort=name --mtime="@$SOURCE_DATE_EPOCH" \
                      -czf $out $name-versioned
                '';
                doVersionedUpdate = ''
                  cargo vendor --versioned-dirs $name-versioned
                '';

                remacsLibDeps = prev.rustPlatform.fetchCargoTarball {
                  src = emacsNgSource + /rust_src/ng-docfile;
                  name = "remacsLibDeps";
                  cargoUpdateHook =
                    let
                      pathDir = emacsNgSource + /rust_src/crates;
                    in
                    ''
                      cp -r ${pathDir} /build/crates
                    '' + doVersionedUpdate;
                  sha256 = "sha256-W/A3mYNBLZrcjL9ehXe6ndjv/bMiUdRDTylAM9hLeoo=";
                  inherit installPhase;
                };

                remacsBindings = prev.rustPlatform.fetchCargoTarball {
                  src = emacsNgSource + "/rust_src/remacs-bindings";
                  sourceRoot = null;
                  cargoUpdateHook = doVersionedUpdate;
                  name = "remacsBindings";
                  sha256 = "sha256-537/sJVxRe9qIGrmzrkKU7INdEXR0hGRBYatlz+aXms=";
                  inherit installPhase;
                };

                remacsSrc = prev.rustPlatform.fetchCargoTarball {
                  src = emacsNgSource + "/rust_src";
                  cargoUpdateHook = ''
                    sed -e 's/@CARGO_.*@//' Cargo.toml.in > Cargo.toml
                  '' + doVersionedUpdate;
                  name = "remacsSrc";
                  sha256 = "sha256-d8Fvg+FrYNVTZAU/QRyvSPuSXbqncg3LaEOWeZzSa8Q=";
                  inherit installPhase;
                };

                remacsHashdir = prev.rustPlatform.fetchCargoTarball {
                  src = emacsNgSource + "/lib-src/hashdir";
                  sourceRoot = null;
                  name = "remacsHashdir";
                  cargoUpdateHook = doVersionedUpdate;
                  sha256 = "sha256-UseR96MO9J+g/G+MUTkoxF95Y4r53xbY/5iBNyJajgA=";
                  inherit installPhase;
                };
              in
              stdenv.mkDerivation {
                name = "emacsNg-rust";
                srcs = [
                  remacsLibDeps
                  remacsBindings
                  remacsHashdir
                  remacsSrc
                ];
                sourceRoot = ".";
                phases = [ "unpackPhase" "installPhase" ];
                installPhase = ''
                  mkdir -p $out/.cargo/registry
                  cat > $out/.cargo/config.toml << EOF
                    [source.crates-io]
                    registry = "https://github.com/rust-lang/crates.io-index"
                    replace-with = "vendored-sources"
                    [source.vendored-sources]
                    directory = "$out/.cargo/registry"
                  EOF
                  cp -R remacsLibDeps-vendor.tar.gz-versioned/* $out/.cargo/registry
                  cp -R remacsBindings-vendor.tar.gz-versioned/* $out/.cargo/registry
                  cp -R remacsHashdir-vendor.tar.gz-versioned/* $out/.cargo/registry
                  cp -R remacsSrc-vendor.tar.gz-versioned/* $out/.cargo/registry
                '';
              }
            );

          librusty_v8 = prev.callPackage ./nix/librusty_v8.nix { };

          emacsNg = with prev; let
            withWebreader = false;
          in
          (
            final.emacsGcc.override
              ({
                withImageMagick = true;
                imagemagick = prev.imagemagick;
              })
          ).overrideAttrs
            (old:
              let
                custom-llvmPackages = prev.llvmPackages_10;
                #withGLX
                rpathLibs =
                  (with xorg; lib.optionals (stdenv.isLinux && withWebreader) [
                    libX11
                    libGLU
                    libGL
                    libXpm
                    libXext
                    libXxf86vm
                    alsaLib
                    libxkbcommon
                    wayland
                    libxcb
                  ]);
              in
              rec {
                name = "emacsNg-" + version;
                src = emacsNgSource;
                version = builtins.substring 0 7 emacsNgSource.rev;
                #version = "develop";

                preConfigure = (old.preConfigure or "") + ''
                '' + lib.optionalString withWebreader ''
                  export NIX_CFLAGS_LINK="$NIX_CFLAGS_LINK -lxcb-render -lxcb-xfixes -lxcb-shape"
                '';

                patches = (old.patches or [ ]) ++ [
                ];

                makeFlags =
                  (old.makeFlags or [ ]) ++ [
                    "CARGO_FLAGS=--offline" #nightly channel
                  ];

                #custom configure Flags Setting
                configureFlags = (if withWebreader then
                  lib.subtractLists [
                    "--with-x-toolkit=gtk3"
                    "--with-xft"
                    "--with-harfbuzz"
                    "--with-cairo"
                    "--with-imagemagick"
                  ]
                    old.configureFlags else
                  old.configureFlags) ++ [
                  "--with-json"
                  "--with-threads"
                  "--with-included-regex"
                  "--with-compress-install"
                  "--with-zlib"
                  "--with-dumping=pdumper"
                ] ++ lib.optionals withWebreader [
                  "--with-webrender"
                ] ++ lib.optionals (! withWebreader) [
                  "--with-harfbuzz"
                ] ++ lib.optionals stdenv.isLinux [
                  "--with-dbus"
                ];

                preBuild =
                  let arch = rust.toRustTarget stdenv.hostPlatform;
                  in
                  (old.preBuild or "") + ''
                    _librusty_v8_setup() {
                        for v in "$@"; do
                          install -D ${final.librusty_v8} "rust_src/target/$v/gn_out/obj/librusty_v8.a"
                        done
                      }
                      _librusty_v8_setup "debug" "release" "${arch}/release"
                        sed -i 's|deno = { git = "https://github.com/DavidDeSimone/deno", branch = "emacs-ng"|deno = { version = "1.9.2"|' rust_src/Cargo.toml
                        sed -i 's|deno_runtime = { git = "https://github.com/DavidDeSimone/deno", branch = "emacs-ng"|deno_runtime = { version = "0.13.0"|' rust_src/Cargo.toml
                        sed -i 's|deno_core = { git = "https://github.com/DavidDeSimone/deno"|deno_core = { version = "0.86.0"|' rust_src/Cargo.toml
                      export HOME=${final.emacsNg-rust}
                  '';

                postPatch = (old.postPatch or "") + ''
                  pwd="$(type -P pwd)"
                  substituteInPlace Makefile.in --replace "/bin/pwd" "$pwd"
                  substituteInPlace lib-src/Makefile.in --replace "/bin/pwd" "$pwd"
                '';

                LIBCLANG_PATH = "${custom-llvmPackages.libclang}/lib";
                RUST_BACKTRACE = "full";

                buildInputs = (old.buildInputs or [ ]) ++
                [
                  custom-llvmPackages.clang
                  custom-llvmPackages.libclang
                  final.rust-bin.nightly."${locked-date}".default
                ] ++ lib.optionals withWebreader (with xorg;[
                  python3
                  rpathLibs
                ]) ++ lib.optionals
                  stdenv.isDarwin
                  (with darwin.apple_sdk.frameworks; with darwin; [
                    libobjc
                    Security
                    CoreServices
                    Metal
                    Foundation
                    libiconv
                  ] ++ lib.optionals (withWebreader && stdenv.isDarwin) [
                    AppKit
                    CoreGraphics
                    CoreServices
                    CoreText
                    Foundation
                    OpenGL
                  ]);



                postFixup = (old.postFixup or "") + (if withWebreader then
                  lib.concatStringsSep "\n" [
                    (lib.optionalString stdenv.isLinux ''
                      patchelf --set-rpath \
                        "$(patchelf --print-rpath "$out/bin/.emacs-28.0.50-wrapped"):${lib.makeLibraryPath rpathLibs}" \
                        "$out/bin/.emacs-28.0.50-wrapped"
                        patchelf --add-needed "libfontconfig.so" "$out/bin/.emacs-28.0.50-wrapped"
                    '')
                  ] else "");
              });
        };
    };
}
