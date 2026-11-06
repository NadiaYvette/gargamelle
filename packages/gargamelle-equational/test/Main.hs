{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Main (main) where

import Test.Hspec
import Data.Proxy (Proxy(..))
import qualified Data.IntMap.Strict as IntMap
import qualified Data.IntSet as IntSet
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import qualified Equational as Eq
import Gargamelle.Core.Institution.Liquid
import Gargamelle.Equational.AbductiveEGraph
import Gargamelle.Equational.DPO
import Gargamelle.FOL.LiquidHyperdoctrine
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

  -- Tested against Note [Presheaf Double-Pushout Gluing Conditions] [ref:note-dpo-gluing-conditions]
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

  describe "Gargamelle.Equational.AbductiveEGraph" do
    let ctx = Context (Map.singleton "x" SortInt)
        qualPos = Qualifier "Q_pos" [("n", SortInt)] (PRel Gt (PVar "n") (PIntLit 0))
        qualNonNeg = Qualifier "Q_nonneg" [("n", SortInt)] (PRel Ge (PVar "n") (PIntLit 0))
        basis = QualifierBasis (Set.fromList [qualPos, qualNonNeg])
        emptySig = LiquidSig Set.empty Map.empty [] Set.empty Map.empty []

        model1 = LiquidModel (Map.singleton "x" (VInt 10)) Map.empty Map.empty
        model2 = LiquidModel (Map.singleton "x" (VInt (-5))) Map.empty Map.empty
        modelMap = IntMap.fromList [(1, model1), (2, model2)]

        evalM (LiquidModel env _ _) = \case
          PRel Gt (PVar "x") (PIntLit 0) -> case Map.lookup "x" env of
            Just (VInt i) -> i > 0
            _             -> False
          PRel Ge (PVar "x") (PIntLit 0) -> case Map.lookup "x" env of
            Just (VInt i) -> i >= 0
            _             -> False
          PTrue -> True
          PFalse -> False
          _ -> False

    it "1. applyAbductiveDPORule abducts valid qualifier guards and attaches AbductiveEdge" do
      let eg0 = emptyAbductiveEGraph ctx emptySig basis modelMap evalM
          eg1 = addEClass (EClassId 0) SortInt [] (Set.singleton (EVar "x")) eg0
          eg2 = addEClass (EClassId 1) SortInt [] (Set.singleton (EIntLit 42)) eg1

          rule = DPORule
            { dpoName       = "rule_pos_to_42"
            , dpoSort       = SortInt
            , dpoMatchLHS   = \_ _ -> [(Map.empty, TVar "x", TIntLit 42)]
            , dpoRHSBuilder = \_ g -> (EClassId 1, g)
            , dpoExtraOblig = \_ -> PRel Gt (PVar "x") (PIntLit 0)
            , dpoCostDelta  = 1
            }

      egRewritten <- applyAbductiveDPORule Z3Hyperdoctrine rule (EClassId 0) eg2
      case IntMap.lookup 0 (egClasses egRewritten) of
        Nothing -> expectationFailure "Expected class 0 in e-graph"
        Just cData -> case ecEdges cData of
          (edge:_) -> do
            edgeRuleName edge `shouldBe` "rule_pos_to_42"
            edgeTarget edge `shouldBe` EClassId 1
            -- Should have abducted guard x > 0 or equivalent
            Set.null (qcConjuncts (edgeGuard edge)) `shouldBe` False
            -- Only model 1 satisfies x > 0 (since x = 10 > 0, while model 2 has x = -5)
            edgeModelCover edge `shouldBe` IntSet.singleton 1
          [] -> expectationFailure "Expected at least one edge in class 0"

    it "2. propagateGuardedFrontiers propagates candidates across e-nodes and edges" do
      let eg0 = emptyAbductiveEGraph ctx emptySig basis modelMap evalM
          eg1 = addEClass (EClassId 0) SortInt [] Set.empty eg0
          eg2 = addEClass (EClassId 1) SortInt [] (Set.singleton (EIntLit 42)) eg1

          edge = AbductiveEdge
            { edgeRuleName   = "edge_0_to_1"
            , edgeTarget     = EClassId 1
            , edgeGuard      = QualifierConj (Set.singleton (PRel Gt (PVar "x") (PIntLit 0)))
            , edgeModelCover = IntSet.singleton 1
            , edgeCostDelta  = 2
            }
          updateClass cd = cd { ecEdges = [edge] }
          eg3 = eg2 { egClasses = IntMap.adjust updateClass 0 (egClasses eg2) }

          egProp = propagateGuardedFrontiers 5 eg3

      case (IntMap.lookup 0 (egClasses egProp), IntMap.lookup 1 (egClasses egProp)) of
        (Just c0, Just c1) -> do
          -- Class 1 has TIntLit 42 with cost 1
          case ecFrontier c1 of
            (fc1:_) -> candTerm fc1 `shouldBe` TIntLit 42
            []      -> expectationFailure "Expected frontier candidates in class 1"
          -- Class 0 should have propagated candidate from class 1 via edge
          let frontier0 = ecFrontier c0
          length frontier0 `shouldSatisfy` (> 0)
          any (\c -> candTerm c == TIntLit 42) frontier0 `shouldBe` True
        _ -> expectationFailure "Expected classes 0 and 1"

    it "3. solveWeightedSetCover assembles minimal-cost covers" do
      -- Universe {1, 2}
      let universe = IntSet.fromList [1, 2]
          candA = GuardedCandidate (TIntLit 1) (QualifierConj Set.empty) (IntSet.singleton 1) 2
          candB = GuardedCandidate (TIntLit 2) (QualifierConj Set.empty) (IntSet.singleton 2) 3
          candBoth = GuardedCandidate (TIntLit 3) (QualifierConj Set.empty) universe 3

      -- candBoth covers {1, 2} at cost 3 (ratio 1.5), which is cheaper than candA (ratio 2.0)
      case solveWeightedSetCover universe [candA, candB, candBoth] of
        Nothing -> expectationFailure "Expected valid set cover"
        Just cover -> do
          map candTerm cover `shouldBe` [TIntLit 3]

      -- When candBoth has cost 10, candA + candB should be chosen
      let candBothExpensive = GuardedCandidate (TIntLit 3) (QualifierConj Set.empty) universe 10
      case solveWeightedSetCover universe [candA, candB, candBothExpensive] of
        Nothing -> expectationFailure "Expected valid set cover"
        Just cover -> do
          let terms = map candTerm cover
          terms `shouldMatchList` [TIntLit 1, TIntLit 2]

    it "4. foldIntoDecisionTree produces correct TIf decision trees" do
      let guard1 = QualifierConj (Set.singleton (PRel Gt (PVar "x") (PIntLit 0)))
          cand1 = GuardedCandidate (TIntLit 42) guard1 (IntSet.singleton 1) 1
          cand2 = GuardedCandidate (TIntLit 0) (QualifierConj Set.empty) (IntSet.singleton 2) 1

          tree = foldIntoDecisionTree [cand1, cand2]
      tree `shouldBe` TIf (PRel Gt (PVar "x") (PIntLit 0)) (TIntLit 42) (TIntLit 0)

    it "5. extractVerifiedDecisionTree extracts complete verified decision tree" do
      let eg0 = emptyAbductiveEGraph ctx emptySig basis modelMap evalM
          guard1 = QualifierConj (Set.singleton (PRel Gt (PVar "x") (PIntLit 0)))
          cand1 = GuardedCandidate (TIntLit 42) guard1 (IntSet.singleton 1) 2
          guard2 = QualifierConj (Set.singleton (PRel Ge (PVar "x") (PIntLit 0)))
          cand2 = GuardedCandidate (TIntLit (-1)) guard2 (IntSet.singleton 2) 2

          c0 = EClassData
            { ecId       = EClassId 0
            , ecSort     = SortInt
            , ecNodes    = Set.empty
            , ecEdges    = []
            , ecMeasures = []
            , ecFrontier = [cand1, cand2]
            }
          eg1 = eg0 { egClasses = IntMap.singleton 0 c0 }

          spec = RBase "v" SortInt PTrue

      mTree <- extractVerifiedDecisionTree Z3Hyperdoctrine Z3StreamSession (EClassId 0) spec eg1
      case mTree of
        Nothing -> expectationFailure "Expected extracted decision tree"
        Just tree -> do
          tree `shouldBe` TIf (PRel Gt (PVar "x") (PIntLit 0)) (TIntLit 42) (TIntLit (-1))
