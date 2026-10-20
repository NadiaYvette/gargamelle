# default.nix — Native Nixpkgs derivation for Gargamelle multi-package suite
{ pkgs ? import <nixpkgs> {}, compiler ? "ghc910" }:

let
  hp = pkgs.haskell.packages.${compiler}.override {
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
in {
  inherit (hp)
    gargamelle-logic
    gargamelle-model
    gargamelle-core
    gargamelle-fol
    gargamelle-equational
    gargamelle-evidence
    gargamelle-effect
    gargamelle-persistence
    gargamelle-sandbox
    gargamelle-sheaf
    gargamelle-workflow;
}
