{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant id" #-}

module Main (main) where

import Test.Hspec
import Control.Category (Category(..))
import Data.Profunctor (Strong(..), Choice(..))
import Algebra.Lattice (Lattice(..), BoundedMeetSemiLattice(..))
import Gargamelle.Logic.Signature
import Gargamelle.Logic.Defunctionalize
import Gargamelle.Logic.Contract
import Gargamelle.Logic.Galois
import Prelude hiding (id, (.))

main :: IO ()
main = hspec $ do
  describe "Gargamelle.Logic.Signature" $ do
    -- See Note [Flat Logic AST Representation] [ref:note-flat-logic-ast]
    it "constructs first-order LogicAST trees and flat connectives" $ do
      let phi = Implies (AtomPred "P" ["x"]) (Or (AtomPred "Q" ["x"]) LitFalse)
      phi `shouldBe` Implies (AtomPred "P" ["x"]) (Or (AtomPred "Q" ["x"]) LitFalse)
      let flat = FlatConj [LitTrue, AtomPred "R" ["y"]]
      flat `shouldBe` FlatConj [LitTrue, AtomPred "R" ["y"]]

  describe "Gargamelle.Logic.Defunctionalize (ObsMor)" $ do
    -- See Note [Defunctionalized Observable Morphisms] [ref:note-defunctionalized-obsmor]
    it "obeys Category identity and composition laws" $ do
      let stepA = SymbolicStep "add1" (+ (1 :: Int))
      let stepB = SymbolicStep "mul2" (* (2 :: Int))
      let comp = stepB . stepA
      evalObsMor comp 5 `shouldBe` 12
      -- Left and right identities
      evalObsMor (id . stepA) 5 `shouldBe` 6
      evalObsMor (stepA . id) 5 `shouldBe` 6

    it "supports Profunctor, Strong, and Choice combinators" $ do
      let step = SymbolicStep "double" (* (2 :: Int))
      let strongStep = first' step
      evalObsMor strongStep (3, "hello") `shouldBe` (6, "hello")
      let choiceStep = left' step
      evalObsMor choiceStep (Left 4 :: Either Int String) `shouldBe` Left 8
      evalObsMor choiceStep (Right "world" :: Either Int String) `shouldBe` Right "world"

    it "provides 100% static inspection without executing steps" $ do
      let stepA = SymbolicStep "validateInput" (+ (1 :: Int))
      let stepB = ProjectTag "payload" (* (2 :: Int))
      let stepC = InjectTag "envelope" (+ (10 :: Int))
      let pipe = stepC . stepB . stepA
      inspectObsMor pipe `shouldBe` ["Step:validateInput", "ProjectTag:payload", "InjectTag:envelope"]

  describe "Gargamelle.Logic.Contract (Assume-Guarantee via Op)" $ do
    -- See Note [Lattice Inversion via Op Dualization] [ref:note-lattice-op-dualization]
    it "dualizes refinement: meet weakens assumptions and strengthens guarantees" $ do
      -- In Bool lattice: False <= True (False is bottom, True is top)
      -- A1 = False (demanding assumption), G1 = False (weak guarantee)
      -- A2 = True (relaxed assumption), G2 = True (strong guarantee)
      let c1 = contract False False
      let c2 = contract True True
      -- Refinement (meet)
      let refined = c1 /\ c2
      -- Refined assumption: Op False /\ Op True = Op (False \/ True) = Op True (relaxed/weakened)
      getAssumption refined `shouldBe` True
      -- Refined guarantee: False /\ True = False (strengthened/meet)
      getGuarantee refined `shouldBe` False

    it "respects top and bottom contract bounds" $ do
      let topContract = top :: AGContract Bool Bool
      -- Top has minimum assumption (bottom of base lattice: False) and maximum guarantee (True)
      getAssumption topContract `shouldBe` False
      getGuarantee topContract `shouldBe` True

    -- See Note [Circular Assume-Guarantee Soundness] [ref:note-circular-ag-soundness]
    it "verifies circular assume-guarantee soundness on shared interfaces" $ do
      -- C1 assumes True, guarantees True
      -- C2 assumes True, guarantees True
      let c1 = contract True True
      let c2 = contract True True
      verifyCircularAG c1 c2 `shouldBe` True
      -- If C1 guarantees False while C2 assumes True, verification fails
      let cBroken = contract True False
      verifyCircularAG cBroken c2 `shouldBe` False

  describe "Gargamelle.Logic.Galois" $ do
    -- See Note [Adjoint Restrict-CoRestrict Galois Connections] [ref:note-galois-connection-stalks]
    it "composes Galois connections in series" $ do
      let g1 = galoisObsMor "g1" (+ (1 :: Int)) (\x -> x - (1 :: Int))
      let g2 = galoisObsMor "g2" (* (2 :: Int)) (`div` (2 :: Int))
      let gComp = composeGalois g2 g1
      evalObsMor (restrict gComp) 4 `shouldBe` 10  -- (4 + 1) * 2
      evalObsMor (coRestrict gComp) 10 `shouldBe` 4 -- (10 `div` 2) - 1
