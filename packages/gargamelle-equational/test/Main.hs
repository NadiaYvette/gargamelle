{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}

module Main (main) where

import Test.Hspec
import Data.Proxy (Proxy(..))
import qualified Data.Map.Strict as Map

import qualified Equational as Eq
import Gargamelle.Equational.DPO
import qualified Institution as Legacy
import Proarrow.Category.Instance.FinHask (FINHASK(..), Fin, FinHask, fromList)

main :: IO ()
main = hspec do
  describe "Equational Logic Institution" do
    it "evaluates algebraic equations under an equational interpretation model" do
      let constC = Eq.Const (Proxy @"c")
          termFC = Eq.FunApp (Proxy @"f") [constC]
          eqnValid = Eq.Equation termFC constC
          model = Eq.EqModel
            { Eq.carrier = ["c", "d"]
            , Eq.interp  = Map.fromList [("f", \case (x:_) -> x; [] -> "")] -- identity on carrier
            }
      Legacy.satisfies (Proxy @(Eq.EGSym '["f", "c"])) model eqnValid `shouldBe` True

    it "rejects invalid equations where interpretations disagree" do
      let constC = Eq.Const (Proxy @"c")
          constD = Eq.Const (Proxy @"d")
          termFC = Eq.FunApp (Proxy @"f") [constC]
          eqnInvalid = Eq.Equation termFC constD
          model = Eq.EqModel
            { Eq.carrier = ["c", "d"]
            , Eq.interp  = Map.fromList [("f", \case (x:_) -> x; [] -> "")] -- f("c") = "c" /= "d"
            }
      Legacy.satisfies (Proxy @(Eq.EGSym '["f", "c", "d"])) model eqnInvalid `shouldBe` False

  describe "Double-Pushout (DPO) Rewriting (Proarrow.Tools.DPO)" do
    it "successfully applies a DPO rule under an injective match" do
      -- Span: Fin 2 <- Fin 1 -> Fin 2
      -- Rule keeps element 0, deletes element 1, creates element 1 in R
      let leftLeg :: FinHask (FH (Fin 1)) (FH (Fin 2))
          leftLeg = fromList [(0, 0)]
          rightLeg :: FinHask (FH (Fin 1)) (FH (Fin 2))
          rightLeg = fromList [(0, 1)]
          rule = makeRule leftLeg rightLeg
          -- Match on host Fin 2 is identity
          match :: FinHask (FH (Fin 2)) (FH (Fin 2))
          match = fromList [(0, 0), (1, 1)]

      isDPOApplicable rule match `shouldBe` True

      case applyDPO rule match of
        DPOSuccess _d2g _d2h _r2h -> True `shouldBe` True
        DPOGluingFailed           -> expectationFailure "Expected DPOSuccess, but gluing condition failed"

    it "refuses DPO rule application when match identifies a kept element with a deleted element" do
      let leftLeg :: FinHask (FH (Fin 1)) (FH (Fin 2))
          leftLeg = fromList [(0, 0)]
          rightLeg :: FinHask (FH (Fin 1)) (FH (Fin 2))
          rightLeg = fromList [(0, 0)]
          rule = makeRule leftLeg rightLeg
          -- Match non-injectively identifies element 0 (kept) with element 1 (deleted)
          matchIdent :: FinHask (FH (Fin 2)) (FH (Fin 1))
          matchIdent = fromList [(0, 0), (1, 0)]

      isDPOApplicable rule matchIdent `shouldBe` False

      case applyDPO rule matchIdent of
        DPOGluingFailed -> True `shouldBe` True
        DPOSuccess{}    -> expectationFailure "Expected DPOGluingFailed on identification conflict"
