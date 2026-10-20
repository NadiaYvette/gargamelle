{
  description = "gargamelle — autonomous synthesis orchestration, categorical institutions, cellular sheaves, and CEGIS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };

        mkGargamellePackages = hp: hp.override {
          overrides = _hfinal: hprev: {
            gargamelle-logic = hprev.callCabal2nix "gargamelle-logic" ./packages/gargamelle-logic {};
            gargamelle-model = hprev.callCabal2nix "gargamelle-model" ./packages/gargamelle-model {};
            gargamelle-core = hprev.callCabal2nix "gargamelle-core" ./packages/gargamelle-core {};
            gargamelle-fol = hprev.callCabal2nix "gargamelle-fol" ./packages/gargamelle-fol {};
            gargamelle-equational = hprev.callCabal2nix "gargamelle-equational" ./packages/gargamelle-equational {};
            gargamelle-evidence = hprev.callCabal2nix "gargamelle-evidence" ./packages/gargamelle-evidence {};
            gargamelle-effect = hprev.callCabal2nix "gargamelle-effect" ./packages/gargamelle-effect {};
            gargamelle-persistence = hprev.callCabal2nix "gargamelle-persistence" ./packages/gargamelle-persistence {};
            gargamelle-sandbox = hprev.callCabal2nix "gargamelle-sandbox" ./packages/gargamelle-sandbox {};
            gargamelle-sheaf = hprev.callCabal2nix "gargamelle-sheaf" ./packages/gargamelle-sheaf {};
            gargamelle-workflow = hprev.callCabal2nix "gargamelle-workflow" ./packages/gargamelle-workflow {};
          };
        };

        hp96 = mkGargamellePackages pkgs.haskell.packages.ghc96;
        hp98 = mkGargamellePackages pkgs.haskell.packages.ghc98;
        hp910 = mkGargamellePackages pkgs.haskell.packages.ghc910;

        cLibraries = with pkgs; [
          zlib
          gmp
          sqlite
          ncurses
          libffi
          bubblewrap
          z3
        ];

        mkDevShell = compilerPkg: pkgs.mkShell {
          buildInputs = [
            compilerPkg
            pkgs.cabal-install
            pkgs.pkg-config
          ] ++ cLibraries;

          shellHook = ''
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath cLibraries}:$LD_LIBRARY_PATH"
          '';
        };
      in {
        packages = {
          default = hp910.gargamelle-workflow;

          ghc96-workflow = hp96.gargamelle-workflow;
          ghc98-workflow = hp98.gargamelle-workflow;
          ghc910-workflow = hp910.gargamelle-workflow;

          ghc96-core = hp96.gargamelle-core;
          ghc98-core = hp98.gargamelle-core;
          ghc910-core = hp910.gargamelle-core;

          ghc96-sheaf = hp96.gargamelle-sheaf;
          ghc98-sheaf = hp98.gargamelle-sheaf;
          ghc910-sheaf = hp910.gargamelle-sheaf;
        };

        devShells = {
          default = mkDevShell pkgs.haskell.compiler.ghc910;
          ghc96 = mkDevShell pkgs.haskell.compiler.ghc96;
          ghc98 = mkDevShell pkgs.haskell.compiler.ghc98;
          ghc910 = mkDevShell pkgs.haskell.compiler.ghc910;
        };
      }
    );
}
