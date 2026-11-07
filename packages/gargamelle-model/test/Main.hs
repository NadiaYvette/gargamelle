{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
module Main (main) where

import Test.Hspec
import Data.Functor.Contravariant (contramap)
import Data.Functor.Contravariant.Divisible (conquer, divide, choose)
import qualified Data.IntMap.Strict as IntMap
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Gargamelle.Model.Satisfaction
import Gargamelle.Model.Structure
import Gargamelle.Model.AmbiguityOracle
import Gargamelle.Core.Institution.Liquid
import Gargamelle.FOL.LiquidHyperdoctrine
import Gargamelle.Equational.AbductiveEGraph (AbductiveEGraph (..), emptyAbductiveEGraph, Z3StreamSession (..))

main :: IO ()
main = hspec $ do
  describe "Gargamelle.Model.Satisfaction (Evidence Monoid)" $ do
    it "treats VerifiedSection as identity" $ do
      let v = VerifiedSection
      let c = Counterexample "sym" "witness"
      (v <> c) `shouldBe` c
      (c <> v) `shouldBe` c
      (mempty :: Evidence) `shouldBe` VerifiedSection

    it "accumulates multiple counterexamples" $ do
      let c1 = Counterexample "boundCheck" "x > 10"
      let c2 = Counterexample "typeCheck" "expected Int"
      let acc = c1 <> c2
      case acc of
        Counterexample sym payload -> do
          sym `shouldBe` "boundCheck; typeCheck"
          payload `shouldBe` "x > 10 | expected Int"
        VerifiedSection -> expectationFailure "Expected Counterexample, got VerifiedSection"

  describe "Gargamelle.Model.Satisfaction (Free Verifier AST)" $ do
    it "evaluates conquer as universally verified" $ do
      let v = conquer :: Verifier Int
      evalVerifier v 42 `shouldBe` VerifiedSection

    it "evaluates atomic predicates" $ do
      let v = verifyPredicate "isPositive" (> (0 :: Int))
      evalVerifier v 5 `shouldBe` VerifiedSection
      evalVerifier v (-2) `shouldBe` Counterexample "isPositive" "Predicate violated: isPositive"

    it "composes verifiers across products via Divisible divide" $ do
      let vInt = verifyPredicate "pos" (> (0 :: Int))
      let vStr = verifyPredicate "nonEmpty" (not . null :: String -> Bool)
      let vPair = divide id vInt vStr
      evalVerifier vPair (5, "hello") `shouldBe` VerifiedSection
      evalVerifier vPair (-1, "hello") `shouldBe` Counterexample "pos" "Predicate violated: pos"
      evalVerifier vPair (5, "") `shouldBe` Counterexample "nonEmpty" "Predicate violated: nonEmpty"
      case evalVerifier vPair (-1, "") of
        Counterexample sym _ -> sym `shouldBe` "pos; nonEmpty"
        VerifiedSection -> expectationFailure "Expected Counterexample, got VerifiedSection"

    it "composes verifiers across sums via Decidable choose" $ do
      let vInt = verifyPredicate "even" (\n -> (n `mod` (2 :: Int)) == 0)
      let vStr = verifyPredicate "validTag" (== "OK")
      let vEither = choose id vInt vStr
      evalVerifier vEither (Left 4 :: Either Int String) `shouldBe` VerifiedSection
      evalVerifier vEither (Left 3 :: Either Int String) `shouldBe` Counterexample "even" "Predicate violated: even"
      evalVerifier vEither (Right "OK" :: Either Int String) `shouldBe` VerifiedSection
      evalVerifier vEither (Right "ERR" :: Either Int String) `shouldBe` Counterexample "validTag" "Predicate violated: validTag"

    it "supports contravariant pre-composition" $ do
      let vLength = verifyPredicate "short" (<= (5 :: Int))
      let vStrLength = contramap (length :: String -> Int) vLength
      evalVerifier vStrLength ("abc" :: String) `shouldBe` VerifiedSection
      evalVerifier vStrLength ("abcdefgh" :: String) `shouldBe` Counterexample "short" "Predicate violated: short"

    it "provides 100% static inspection of the verification plan" $ do
      let v1 = verifyPredicate "pos" (> (0 :: Int))
      let v2 = verifyPredicate "nonEmpty" (not . null :: String -> Bool)
      let vPair = divide id v1 v2
      inspectVerifierPlan vPair `shouldBe` ["Step:divide", "AtomCheck:pos", "AtomCheck:nonEmpty"]

  describe "Gargamelle.Model.Structure" $ do
    it "evaluates compilePairVerifier and compileEitherVerifier helpers" $ do
      let vA = verifyPredicate "gtZero" (> (0 :: Int))
      let vB = verifyPredicate "gtTen" (> (10 :: Int))
      let vPair = compilePairVerifier vA vB
      evalVerifier vPair (1, 20) `shouldBe` VerifiedSection
      let vEither = compileEitherVerifier vA vB
      evalVerifier vEither (Left 2) `shouldBe` VerifiedSection
      evalVerifier vEither (Right 5) `shouldBe` Counterexample "gtTen" "Predicate violated: gtTen"

  describe "Gargamelle.Model.AmbiguityOracle" $ do
    it "1. compileSynTermToRelPred lowers branching SynTerm into relational SMT predicates" $ do
      -- Branching term: if x > 0 then x + 1 else 0
      let term = TIf (PRel Gt (PVar "x") (PIntLit 0))
                     (TApp (TVar "add") [TVar "x", TIntLit 1])
                     (TIntLit 0)
          rel = compileSynTermToRelPred "out" term
      case rel of
        PAnd [PImplies cond1 thenRel, PImplies cond2 elseRel] -> do
          cond1 `shouldBe` PRel Gt (PVar "x") (PIntLit 0)
          cond2 `shouldBe` PNot (PRel Gt (PVar "x") (PIntLit 0))
          thenRel `shouldBe` PRel Eq (PVar "out") (PBinOp Add (PVar "x") (PIntLit 1))
          elseRel `shouldBe` PRel Eq (PVar "out") (PIntLit 0)
        _ -> expectationFailure $ "Expected PAnd [PImplies..., PImplies...], got: " ++ show rel

    it "2. evalSynTermInModel evaluates Polytropos record/variant combinators on concrete models" $ do
      let evalMdl _ _ = True
          initialRecord = VRecord (Map.fromList [("quota", VInt 10), ("used", VInt 4)])
          testModel = LiquidModel
            { modelVarEnv        = Map.fromList [("r", initialRecord), ("d", VInt (-8))]
            , modelMeasureInterp = Map.empty
            , modelAbductSol     = Map.empty
            }
          -- getF_quota r
          termGet = TApp (TVar "getF_quota") [TVar "r"]
          -- setF_quota (TIntLit 4) r
          termSet = TApp (TVar "setF_quota") [TIntLit 4, TVar "r"]
          -- injF_some (TIntLit 42)
          termInj = TApp (TVar "injF_some") [TIntLit 42]
          -- matchTagF_some
          termMatch = TApp (TVar "matchTagF_some") [termInj]

      evalSynTermInModel evalMdl testModel termGet `shouldBe` VInt 10
      evalSynTermInModel evalMdl testModel termSet `shouldBe` VRecord (Map.fromList [("quota", VInt 4), ("used", VInt 4)])
      evalSynTermInModel evalMdl testModel termInj `shouldBe` VVariant "some" (VInt 42)
      evalSynTermInModel evalMdl testModel termMatch `shouldBe` VInt 42

    it "3. adjustQuota walkthrough (PDF p. 29)" $ do
      -- Walkthrough setup:
      -- r : RecordF Identity ("quota" :-> Int, "used" :-> Int)
      -- d : Int
      -- Invariant: sel_quota(v) >= sel_used(v) && sel_used(v) = sel_used(r)
      -- T1 (Clamp to used):
      --   if sel_quota(r) + d >= sel_used(r) then setF_quota (getF_quota r + d) r else setF_quota (getF_used r) r
      -- T2 (Reject/No-op on underflow):
      --   if sel_quota(r) + d >= sel_used(r) then setF_quota (getF_quota r + d) r else r
      let recordSort = SortRecordRow (RowSchema (Map.fromList [("quota", SortInt), ("used", SortInt)]))
          guardCond = PRel Ge (PBinOp Add (PMeasureApp "sel_quota" (PVar "r")) (PVar "d"))
                              (PMeasureApp "sel_used" (PVar "r"))

          -- T1: clamp to used on underflow
          t1 = TIf guardCond
                   (TApp (TVar "setF_quota") [TApp (TVar "add") [TApp (TVar "getF_quota") [TVar "r"], TVar "d"], TVar "r"])
                   (TApp (TVar "setF_quota") [TApp (TVar "getF_used") [TVar "r"], TVar "r"])

          -- T2: no-op (keep r unchanged) on underflow
          t2 = TIf guardCond
                   (TApp (TVar "setF_quota") [TApp (TVar "add") [TApp (TVar "getF_quota") [TVar "r"], TVar "d"], TVar "r"])
                   (TVar "r")

          -- Sig: r and d in environment, path condition sel_quota(r) >= sel_used(r) >= 0
          sig0 = LiquidSig
            { sigSorts      = Set.empty
            , sigMeasures   = Map.fromList
                [ ("sel_quota", MeasureDecl "sel_quota" recordSort SortInt False)
                , ("sel_used",  MeasureDecl "sel_used"  recordSort SortInt False)
                ]
            , sigCtorAxioms = []
            , sigQualifiers = Set.empty
            , sigEnv        = Map.fromList
                [ ("r", RBScalar (RBase "v" recordSort PTrue))
                , ("d", RBScalar (RBase "v" SortInt PTrue))
                ]
            , sigPathCond   =
                [ PRel Ge (PMeasureApp "sel_quota" (PVar "r")) (PMeasureApp "sel_used" (PVar "r"))
                , PRel Ge (PMeasureApp "sel_used" (PVar "r")) (PIntLit 0)
                ]
            }

          -- Goal specification: output v satisfies sel_quota(v) >= sel_used(v)
          goalBase = RBase "v" recordSort (PRel Ge (PMeasureApp "sel_quota" (PVar "v")) (PMeasureApp "sel_used" (PVar "v")))
          ctx = Context (Map.fromList [("r", recordSort), ("d", SortInt)])

          -- Qualifiers characterizing Option 0 vs Option 1
          qualClamp = Qualifier "Q_clamp" []
            (PImplies (PNot guardCond)
                      (PRel Eq (PMeasureApp "sel_quota" (PVar "v")) (PMeasureApp "sel_used" (PVar "r"))))
          qualNoOp = Qualifier "Q_noop" []
            (PImplies (PNot guardCond)
                      (PRel Eq (PMeasureApp "sel_quota" (PVar "v")) (PMeasureApp "sel_quota" (PVar "r"))))
          basis = QualifierBasis (Set.fromList [qualClamp, qualNoOp])

          evalPred mdl = \case
            PRel Ge (PBinOp Add (PMeasureApp "sel_quota" (PVar "r")) (PVar "d")) (PMeasureApp "sel_used" (PVar "r")) ->
              let q = case Map.lookup "r" (modelVarEnv mdl) of
                        Just (VRecord m) -> case Map.lookup "quota" m of Just (VInt i) -> i; _ -> 0
                        _ -> 0
                  u = case Map.lookup "r" (modelVarEnv mdl) of
                        Just (VRecord m) -> case Map.lookup "used" m of Just (VInt i) -> i; _ -> 0
                        _ -> 0
                  dVal = case Map.lookup "d" (modelVarEnv mdl) of
                           Just (VInt i) -> i
                           _ -> 0
              in (q + dVal) >= u
            _ -> True

      (quotients, _diffModels) <- partitionIntoSemanticQuotients Z3StreamSession sig0 evalPred recordSort [(t1, 1), (t2, 2)]
      length quotients `shouldBe` 2

      -- Verify on M_diff = {r: {quota: 10, used: 4}, d: -8}
      let mDiff = LiquidModel
            { modelVarEnv = Map.fromList
                [ ("r", VRecord (Map.fromList [("quota", VInt 10), ("used", VInt 4)]))
                , ("d", VInt (-8))
                ]
            , modelMeasureInterp = Map.empty
            , modelAbductSol     = Map.empty
            }
          out1 = evalSynTermInModel evalPred mDiff t1
          out2 = evalSynTermInModel evalPred mDiff t2
      out1 `shouldBe` VRecord (Map.fromList [("quota", VInt 4), ("used", VInt 4)])
      out2 `shouldBe` VRecord (Map.fromList [("quota", VInt 10), ("used", VInt 4)])

      -- B. Verify analyzeStalkAmbiguity constructs AmbiguityQuery with Option 0 and Option 1
      stalkRes <- analyzeStalkAmbiguity Z3Hyperdoctrine Z3StreamSession "adjustQuota" ctx basis sig0 evalPred goalBase [(t1, 1), (t2, 2)]
      case stalkRes of
        AmbiguousStalk query -> do
          aqVertexId query `shouldBe` "adjustQuota"
          case aqBehaviorOptions query of
            (opt0 : opt1 : _) -> do
              optOptionId opt0 `shouldBe` 0
              optOutputValue opt0 `shouldNotBe` optOutputValue opt1
              -- C. Verify applyAmbiguityResolution pins Option 0 and strengthens refinement
              let resolution = AmbiguityResolution "adjustQuota" 0
                  eg0 = emptyAbductiveEGraph ctx sig0 basis IntMap.empty evalPred
                  (strengthenedGoal, pinMorphism, egUpdated) = applyAmbiguityResolution query resolution eg0
              IntMap.size (egWitnessModels egUpdated) `shouldBe` 1
              case IntMap.lookup 0 (egWitnessModels egUpdated) of
                Nothing -> expectationFailure "Expected pinned model at index 0"
                Just pinned -> do
                  Map.lookup "v" (modelVarEnv pinned) `shouldBe` Just (optOutputValue opt0)
              rRefine strengthenedGoal `shouldNotBe` rRefine goalBase
              sigPathCond (morphTarget pinMorphism) `shouldNotBe` sigPathCond sig0
            _ -> expectationFailure "Expected at least 2 behavior options in AmbiguityQuery"
        UnambiguousTerm _ ->
          expectationFailure "Expected AmbiguousStalk for distinct behaviors T1 and T2"
