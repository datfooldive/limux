{
  description = "Limux GTK terminal workspace manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          lib = pkgs.lib;
          manifest = builtins.fromTOML (builtins.readFile ./Cargo.toml);

          runtimeLibs = with pkgs; [
            gtk4
            libadwaita
            webkitgtk_6_0
            libepoxy
            glib-networking
            gsettings-desktop-schemas
          ];
        in
        rec {
          default = limux;

          limux = pkgs.rustPlatform.buildRustPackage {
            pname = "limux";
            version = manifest.workspace.package.version;

            src = lib.cleanSource ./.;

            cargoLock = {
              lockFile = ./Cargo.lock;
            };

            doCheck = false;

            nativeBuildInputs = with pkgs; [
              pkg-config
              wrapGAppsHook4
            ];

            nativeCheckInputs = with pkgs; [
              python3
            ];

            buildInputs = runtimeLibs ++ (with pkgs; [
              gtk4-layer-shell
            ]);

            RUSTFLAGS = lib.concatStringsSep " " [
              "-C link-arg=-Wl,--undefined=gladLoaderLoadGLContext"
              "-C link-arg=-Wl,--undefined=gladLoaderUnloadGLContext"
            ];

            preBuild = ''
              export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
              export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"

              if [ ! -f ghostty/build.zig ]; then
                echo "Ghostty submodule is missing. Run: git submodule update --init --recursive" >&2
                exit 1
              fi

              (cd ghostty && ${pkgs.zig_0_15}/bin/zig build -Dapp-runtime=none -Doptimize=ReleaseFast -Dcpu=baseline)
            '';

            preCheck = ''
              export LD_LIBRARY_PATH="$PWD/ghostty/zig-out/lib:${lib.makeLibraryPath runtimeLibs}:$LD_LIBRARY_PATH"
            '';

            postInstall = ''
              install -Dm755 ghostty/zig-out/lib/libghostty.so "$out/lib/limux/libghostty.so"

              install -Dm644 rust/limux-host-linux/dev.limux.linux.desktop \
                "$out/share/applications/dev.limux.linux.desktop"
              install -Dm644 rust/limux-host-linux/dev.limux.linux.metainfo.xml \
                "$out/share/metainfo/dev.limux.linux.metainfo.xml"

              if [ -d rust/limux-host-linux/icons/hicolor ]; then
                cp -r rust/limux-host-linux/icons/hicolor "$out/share/icons/"
              fi

              if [ -d rust/limux-host-linux/icons/app ]; then
                for size in 16 32 128 256 512; do
                  src="rust/limux-host-linux/icons/app/$size.png"
                  if [ -f "$src" ]; then
                    install -Dm644 "$src" "$out/share/icons/hicolor/''${size}x''${size}/apps/limux.png"
                  fi
                done
              fi
            '';

            preFixup = ''
              gappsWrapperArgs+=(
                --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}:$out/lib/limux"
              )
            '';

            meta = {
              description = "GPU-accelerated terminal workspace manager for Linux";
              homepage = "https://github.com/am-will/limux";
              license = lib.licenses.mit;
              platforms = systems;
              mainProgram = "limux";
            };
          };
        });

      apps = forAllSystems (system: {
        default = self.apps.${system}.limux;

        limux = {
          type = "app";
          program = "${self.packages.${system}.limux}/bin/limux";
        };

        limux-cli = {
          type = "app";
          program = "${self.packages.${system}.limux}/bin/limux-cli";
        };
      });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          lib = pkgs.lib;
          runtimeLibs = with pkgs; [
            gtk4
            libadwaita
            webkitgtk_6_0
            libepoxy
            glib-networking
            gsettings-desktop-schemas
          ];
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              cargo
              clippy
              rustc
              rustfmt
              pkg-config
              zig_0_15
              gtk4-layer-shell
            ] ++ runtimeLibs;

            LD_LIBRARY_PATH = lib.makeLibraryPath runtimeLibs;

            shellHook = ''
              export LD_LIBRARY_PATH="$PWD/ghostty/zig-out/lib:$LD_LIBRARY_PATH"
              echo "Limux dev shell"
              echo "Build Ghostty: (cd ghostty && zig build -Dapp-runtime=none -Doptimize=ReleaseFast)"
              echo "Check: ./scripts/check.sh"
            '';
          };
        });

      formatter = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
        in pkgs.nixpkgs-fmt);
    };
}
