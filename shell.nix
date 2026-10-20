# shell.nix — Development shell for Gargamelle
{ pkgs ? import <nixpkgs> {}, compiler ? "ghc910" }:

let
  cLibraries = with pkgs; [
    zlib
    gmp
    sqlite
    ncurses
    libffi
    bubblewrap
    z3
  ];
in pkgs.mkShell {
  name = "gargamelle-dev-shell";

  buildInputs = [
    pkgs.haskell.compiler.${compiler}
    pkgs.cabal-install
    pkgs.pkg-config
  ] ++ cLibraries;

  shellHook = ''
    export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath cLibraries}:$LD_LIBRARY_PATH"
  '';
}
