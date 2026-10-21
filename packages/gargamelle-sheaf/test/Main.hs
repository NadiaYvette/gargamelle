{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}

module Main (main) where

import Test.Hspec
import qualified Data.Map.Strict as Map
import Algebra.Lattice (Lattice(..), BoundedMeetSemiLattice(..))

import Gargamelle.Sheaf.Complex
import Gargamelle.Sheaf.Diffusion
import Gargamelle.Sheaf.Cohomology

-- A simple bounded lattice of contract specifications for testing diffusion
-- Ordered by specificity / constraint strength: Top is least constrained (True),
-- Safe is constrained, Critical is most constrained, Bottom is contradictory (False).
data ContractLevel = Unconstrained | StandardSecurity | HighIntegrity | Contradiction
  deriving (Eq, Ord, Show)

instance Lattice ContractLevel where
  (/\) = max -- Meet strengthens the contract (higher constraint level)
  (\/) = min -- Join weakens the contract

instance BoundedMeetSemiLattice ContractLevel where
  top = Unconstrained

main :: IO ()
main = hspec do
  describe "Gargamelle.Sheaf.Complex (Finite Cell Complexes & Graded Posets)" do
    it "constructs cell complexes with vertices, edges, and boundary maps" do
      let complex = fromEdges [("e1", "v1", "v2"), ("e2", "v2", "v3")]
      numVertices complex `shouldBe` 3
      numEdges complex `shouldBe` 2
      boundary complex "e1" `shouldBe` Just ("v1", "v2")
      boundary complex "e2" `shouldBe` Just ("v2", "v3")

    it "evaluates face relations (sigma <= tau) and cell dimensions" do
      let complex = fromEdges [("e1", "v1", "v2")]
      cellDimension (Cell0 "v1") `shouldBe` 0
      cellDimension (Cell1 "e1") `shouldBe` 1
      isFaceOf complex (Cell0 "v1") (Cell1 "e1") `shouldBe` True
      isFaceOf complex (Cell0 "v2") (Cell1 "e1") `shouldBe` True
      isFaceOf complex (Cell0 "v3") (Cell1 "e1") `shouldBe` False
      isFaceOf complex (Cell1 "e1") (Cell0 "v1") `shouldBe` False

    it "computes star co-faces and homological incidence signs" do
      let complex = fromEdges [("e1", "v1", "v2"), ("e2", "v2", "v3")]
      star complex "v2" `shouldBe` ["e1", "e2"]
      incidenceSign complex "e1" "v1" `shouldBe` (-1) -- source
      incidenceSign complex "e1" "v2" `shouldBe` 1    -- target
      incidenceSign complex "e1" "v3" `shouldBe` 0    -- non-incident

    it "computes topological Euler characteristic chi = |V| - |E|" do
      let triangle = fromEdges [("e1", "v1", "v2"), ("e2", "v2", "v3"), ("e3", "v3", "v1")]
      eulerCharacteristic triangle `shouldBe` 0
      let tree = fromEdges [("e1", "v1", "v2"), ("e2", "v2", "v3")]
      eulerCharacteristic tree `shouldBe` 1

  -- Tested against Note [Cellular Sheaf Restriction Maps and Stalk Functors] [ref:note-cellular-sheaf-stalks]
  -- and Note [Store Comonad Cellular Diffusion and Harmonic Consensus] [ref:note-store-comonad-diffusion]
  describe "Gargamelle.Sheaf.Diffusion (Store Comonad & Knaster-Tarski)" do
    it "diffuses specifications comonadically across cell boundaries" do
      let complex = fromEdges [("e1", "A", "B"), ("e2", "B", "C")]
          -- Symmetric sheaf where restriction is identity and lifting is identity
          sheaf = symmetricSheaf (\_ c -> c) (\_ e -> e)
          -- Initial cochain: A has HighIntegrity, B and C are Unconstrained
          initialC0 = fromListCochain0
            [ ("A", HighIntegrity)
            , ("B", Unconstrained)
            , ("C", Unconstrained)
            ]
          -- Step 1: HighIntegrity propagates to B
          step1 = stepDiffusion complex sheaf initialC0
      lookupCochain0 "A" step1 `shouldBe` Just HighIntegrity
      lookupCochain0 "B" step1 `shouldBe` Just HighIntegrity
      lookupCochain0 "C" step1 `shouldBe` Just Unconstrained

      -- Step 2: HighIntegrity propagates from B to C
      let step2 = stepDiffusion complex sheaf step1
      lookupCochain0 "C" step2 `shouldBe` Just HighIntegrity

    it "converges to a Knaster-Tarski harmonic fixed point" do
      let complex = fromEdges [("e1", "A", "B"), ("e2", "B", "C")]
          sheaf = symmetricSheaf (\_ c -> c) (\_ e -> e)
          initialC0 = fromListCochain0
            [ ("A", StandardSecurity)
            , ("B", HighIntegrity)
            , ("C", Unconstrained)
            ]
          fixedPoint = diffuseUntilHarmonic 10 complex sheaf initialC0
      -- In the contract meet lattice, HighIntegrity meet StandardSecurity is HighIntegrity
      lookupCochain0 "A" fixedPoint `shouldBe` Just HighIntegrity
      lookupCochain0 "B" fixedPoint `shouldBe` Just HighIntegrity
      lookupCochain0 "C" fixedPoint `shouldBe` Just HighIntegrity

  -- Tested against Note [Sheaf Coboundary Operator and Cohomological Obstructions] [ref:note-sheaf-coboundary-obstructions]
  describe "Gargamelle.Sheaf.Cohomology (Coboundaries, H0 & H1 Localization)" do
    it "identifies harmonic global sections (H0) when boundary restrictions agree" do
      let complex = fromEdges [("e1", "A", "B")]
          sheaf = symmetricSheaf (\_ (portVal :: Int) -> portVal) (\_ e -> e)
          harmonicC0 = fromListCochain0 [("A", 42), ("B", 42)]
          (Cochain1 diffs, harmonic) = coboundary complex sheaf harmonicC0
      harmonic `shouldBe` True
      diffs `shouldBe` Map.fromList [("e1", (42, 42))]
      computeCohomology complex sheaf harmonicC0 `shouldBe` HarmonicSection
      globalSection complex sheaf harmonicC0 `shouldNotBe` Nothing

    it "detects H1 cohomological obstructions and localizes failing interface boundaries" do
      let complex = fromEdges [("e1", "A", "B"), ("e2", "B", "C")]
          sheaf = symmetricSheaf (\_ (v :: String) -> v) (\_ e -> e)
          -- A and B agree on "token_auth", but C provides "cert_auth"
          inconsistentC0 = fromListCochain0
            [ ("A", "token_auth")
            , ("B", "token_auth")
            , ("C", "cert_auth")
            ]
          (Cochain1 diffs, harmonic) = coboundary complex sheaf inconsistentC0
      harmonic `shouldBe` False
      diffs `shouldBe` Map.fromList [("e1", ("token_auth", "token_auth")), ("e2", ("token_auth", "cert_auth"))]

      let obstructions = locateObstructions complex sheaf inconsistentC0
      case obstructions of
        [obs] -> do
          obstructedEdge obs `shouldBe` "e2"
          sourceRestriction obs `shouldBe` "token_auth"
          targetRestriction obs `shouldBe` "cert_auth"
        _ -> expectationFailure "Expected exactly one obstruction"

    it "verifies model amalgamation when boundary restrictions match" do
      -- Pushout diagram model verification:
      -- Component A produces (10, True), Component B produces (True, "ok")
      -- Interface edge requires boolean flag agreement
      let modelA = (10 :: Int, True)
          modelB = (True, "ok" :: String)
          reductA = snd
          reductB = fst
      -- When restrictions agree on True, amalgamation is sound
      (reductA modelA == reductB modelB) `shouldBe` True
      let amalgamated = if reductA modelA == reductB modelB
                          then Just (fst modelA, fst modelB, snd modelB)
                          else Nothing
      amalgamated `shouldBe` Just (10, True, "ok")
