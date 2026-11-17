{
  description = "cktImg: schematics from SPICE netlists (Zig engine, Schemify plugin, LaTeX and JSON tools)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # The engine needs Zig 0.17 (build.zig.zon), which nixpkgs doesn't ship yet.
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      zig-overlay,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      zig = pkgs: zig-overlay.packages.${pkgs.stdenv.hostPlatform.system}."0.17.0";
    in
    {
      # The engine's static library, include/cktimg.h and cktimg-json.
      packages = forAll (pkgs: {
        default = pkgs.stdenv.mkDerivation {
          pname = "cktimg";
          version = "0.1.0";
          src = ./.;
          # Zig 0.17 from zig-overlay: nixpkgs' zig (and its setup hook) is 0.16.
          nativeBuildInputs = [ (zig pkgs) ];
          dontConfigure = true;
          dontInstall = true;
          # `-Dlatex_renderer=true` additionally compiles the TikZ emitter in; it is off by
          # default so consumers who only want geometry do not carry it.
          buildPhase = ''
            export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
            zig build -Doptimize=ReleaseFast --prefix "$out" --cache-dir "$TMPDIR/zig-cache"
          '';
          meta = {
            description = "Place-and-route engine turning an analog netlist into a schematic";
            license = pkgs.lib.licenses.mit;
          };
        };
      });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            # Everything builds with Zig; netlist-import.wasm is byte-reproducible under this one.
            (zig pkgs)
            # Final size-limited WebAssembly link, version pinned through flake.lock.
            binaryen
            # The C ABI is shipped product surface, so the header must keep compiling
            # standalone: cc -std=c99 -Wall -Wextra -pedantic -fsyntax-only include/cktimg.h
            clang-tools
            # Rasterizes gallery SVGs so a layout change can be eyeballed.
            imagemagick
          ];

          shellHook = ''
            echo "cktimg: zig $(zig version)"
            echo "  zig build test                         every suite"
            echo "  zig build -Dschemify_plugin=true       netlist-import.wasm (the Schemify plugin)"
            echo "  zig build gallery -- --svgs out/       draw the textbook circuits"
          '';
        };
      });

      formatter = forAll (pkgs: pkgs.nixfmt);
    };
}
