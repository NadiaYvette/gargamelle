{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main (main) where

import Test.Hspec
import Data.Proxy (Proxy(..))
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import qualified FirstOrder as FO
import qualified Hyperdoctrine as HD
import qualified RefinementCalculus as RC
import Gargamelle.FOL.Z3
import Gargamelle.Model.Satisfaction (Evidence(..))
import qualified Institution as Legacy

main :: IO ()
main = hspec do
  describe "Native FirstOrder Logic" do
    it "evaluates closed first-order formula under a concrete model" do
      let pVar = FO.Pred (Proxy @"p") []
          qVar = FO.Pred (Proxy @"q") []
          formula = FO.And pVar (FO.Not qVar)
          model = FO.FOLModel
            { FO.predicateInterpretation = Map.fromList [("p", Set.singleton []), ("q", Set.empty)]
            , FO.functionInterpretation  = Map.empty
            , FO.constants               = Set.empty
            }
      Legacy.satisfies (Proxy @(FO.FOLSig '["p", "q"])) model formula `shouldBe` True

    it "evaluates universal quantifiers over Herbrand constants" do
      let xVar = FO.var "x"
          predP = FO.Pred (Proxy @"P") [xVar]
          formula = FO.Forall (Proxy @"x") predP
          model = FO.FOLModel
            { FO.predicateInterpretation = Map.fromList [("P", Set.fromList [["c1"], ["c2"]])]
            , FO.functionInterpretation  = Map.empty
            , FO.constants               = Set.fromList ["c1", "c2"]
            }
      Legacy.satisfies (Proxy @(FO.FOLSig '["P"])) model formula `shouldBe` True

  describe "Gargamelle.FOL.Z3 SMT-LIB2 Pipe" do
    it "solves satisfiable formula and extracts model assignments" do
      let pVar = FO.Pred (Proxy @"p") []
          qVar = FO.Pred (Proxy @"q") []
          formula = FO.And pVar (FO.Not qVar)
      res <- checkFormulaZ3 formula
      case res of
        Sat model -> do
          Map.lookup "p" model `shouldBe` Just "true"
          Map.lookup "q" model `shouldBe` Just "false"
        _ -> expectationFailure ("Expected Sat, but got: " ++ show res)

    it "identifies unsatisfiable formula as Unsat" do
      let pVar = FO.Pred (Proxy @"p") []
          formula = FO.And pVar (FO.Not pVar)
      res <- checkFormulaZ3 formula
      res `shouldBe` Unsat

    it "formally verifies tautological validity returning VerifiedSection" do
      -- Law of excluded middle: p \/ (not p) is universally valid
      let pVar = FO.Pred (Proxy @"p") []
          tautology = FO.Or pVar (FO.Not pVar)
      evidence <- verifyValidityZ3 tautology
      evidence `shouldBe` VerifiedSection

    it "detects countermodel when verifying non-valid formula" do
      -- p /\ q is not valid (counterexample exists where p=false)
      let pVar = FO.Pred (Proxy @"p") []
          qVar = FO.Pred (Proxy @"q") []
          nonTautology = FO.And pVar qVar
      evidence <- verifyValidityZ3 nonTautology
      case evidence of
        Counterexample sym _ -> sym `shouldBe` "Z3-Countermodel"
        VerifiedSection      -> expectationFailure "Expected counterexample for non-valid formula"

  describe "Hyperdoctrine & Refinement Calculus" do
    it "evaluates hyperdoctrine context satisfaction" do
      let pVar = FO.Pred (Proxy @"p") []
          model = FO.FOLModel
            { FO.predicateInterpretation = Map.fromList [("p", Set.singleton [])]
            , FO.functionInterpretation  = Map.empty
            , FO.constants               = Set.empty
            }
      Legacy.satisfies (Proxy @(HD.HDCSig '["p"])) model pVar `shouldBe` True

    it "evaluates specification refinement (Spec1 ⊑ Spec2)" do
      let pre1 = FO.Pred (Proxy @"preA") []
          post1 = FO.Pred (Proxy @"postA") []
          pre2 = FO.Pred (Proxy @"preB") []
          post2 = FO.Pred (Proxy @"postB") []
          spec1 = RC.spec pre1 post1
          spec2 = RC.spec pre2 post2
          refinement = RC.refine spec1 spec2
          -- For spec1 to refine spec2: pre2 => pre1 and post1 => post2
          -- We set up a model where pre1, pre2, post1, post2 all hold
          model = FO.FOLModel
            { FO.predicateInterpretation = Map.fromList
                [ ("preA", Set.singleton [])
                , ("postA", Set.singleton [])
                , ("preB", Set.singleton [])
                , ("postB", Set.singleton [])
                ]
            , FO.functionInterpretation  = Map.empty
            , FO.constants               = Set.empty
            }
      Legacy.satisfies (Proxy @(RC.RCSig '["preA", "postA", "preB", "postB"])) model refinement `shouldBe` True
