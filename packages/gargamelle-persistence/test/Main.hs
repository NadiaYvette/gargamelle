{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main (main) where

import Test.Hspec
import Database.SQLite.Simple (open, close)
import qualified Data.IntMap.Strict as IntMap
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import Persistence.Schema
import Persistence.Beam
import Gargamelle.Core.Institution.Liquid
import Gargamelle.Equational.AbductiveEGraph
  ( AbductiveEGraph (..)
  , DPORule (..)
  , EClassData (..)
  , EClassId (..)
  , ENode (..)
  , Z3StreamSession (..)
  , emptyAbductiveEGraph
  , unEClassId
  )
import Gargamelle.FOL.GaloisSeparator (SeparatorSynthesisResult (..))
import Gargamelle.FOL.LiquidHyperdoctrine
import Gargamelle.Persistence.Crystallize
import Gargamelle.Persistence.RewriteMining
import qualified Data.IntSet as IntSet

main :: IO ()
main = hspec do
  -- Tested against Note [Beam SQLite Relational Persistence and Concurrency Locking] [ref:note-beam-sqlite-persistence]
  describe "Beam SQLite Relational Persistence" do
    it "initializes SQLite schema cleanly in-memory" do
      conn <- open ":memory:"
      initEvidenceDb conn
      evList <- listAllEvidence conn
      evList `shouldBe` []
      close conn

    it "persists and retrieves evidence records" do
      conn <- open ":memory:"
      initEvidenceDb conn
      insertEvidenceRecord conn 1 "PropSig" "AstPatchV1" "TypeMismatch" 1600000000
      evs <- listAllEvidence conn
      length evs `shouldBe` 1
      case evs of
        (ev:_) -> do
          evidenceId ev `shouldBe` 1
          evidenceSig ev `shouldBe` "PropSig"
          evidenceChangeRep ev `shouldBe` "AstPatchV1"
          evidenceReason ev `shouldBe` "TypeMismatch"
        [] -> expectationFailure "Expected non-empty evidence list"

      byRep <- findEvidenceByRep conn "AstPatchV1"
      length byRep `shouldBe` 1
      close conn

    it "links counterexamples to evidence via foreign keys" do
      conn <- open ":memory:"
      initEvidenceDb conn
      insertEvidenceRecord conn 10 "FOLSig" "SortPatch" "SMT-Failed" 1600000100
      insertCounterexample conn 100 10 "x = -1, y = 0"

      ces <- findCounterexamplesFor conn 10
      length ces `shouldBe` 1
      case ces of
        (ce:_) -> do
          counterexampleId ce `shouldBe` 100
          counterexamplePayload ce `shouldBe` "x = -1, y = 0"
        [] -> expectationFailure "Expected non-empty counterexample list"
      close conn

    it "tracks autonomous workflow run lifecycle" do
      conn <- open ":memory:"
      initEvidenceDb conn
      startRunRecord conn 42 "InFlight" 1600000200
      completeRunRecord conn 42 "Success" 1600000250
      close conn

  describe "Gargamelle.Persistence.Crystallize (Wake-Sleep Library Consolidation)" do
    let recordSort = SortADT "RecordF_Tenant" [SortRecordRow (RowSchema (Map.fromList [("quota", SortInt), ("used", SortInt), ("owner", SortInt)])), SortVar "rho"]
        guardCond = PRel Ge (PBinOp Add (PMeasureApp "sel_quota" (PVar "r")) (PVar "d"))
                            (PMeasureApp "sel_used" (PVar "r"))
        termT1 = TIf guardCond
                     (TApp (TVar "setF_quota") [TApp (TVar "add") [TApp (TVar "getF_quota") [TVar "r"], TVar "d"], TVar "r"])
                     (TApp (TVar "setF_quota") [TApp (TVar "getF_used") [TVar "r"], TVar "r"])

    it "1. extractAccessedRowLabels extracts read and written Polytropos record labels" do
      let (readLbls, writtenLbls) = extractAccessedRowLabels termT1
      readLbls `shouldBe` Set.fromList ["quota", "used"]
      writtenLbls `shouldBe` Set.singleton "quota"

    it "2. generalizeToOpenRowSchema creates open row tail variable and frame preservation axioms" do
      let sig = LiquidSig
            { sigSorts      = Set.empty
            , sigMeasures   = Map.fromList
                [ ("sel_quota", MeasureDecl "sel_quota" recordSort SortInt False)
                , ("sel_used",  MeasureDecl "sel_used"  recordSort SortInt False)
                ]
            , sigCtorAxioms = []
            , sigQualifiers = Set.empty
            , sigEnv        = Map.fromList [("r", RBScalar (RBase "v" recordSort PTrue)), ("d", RBScalar (RBase "v" SortInt PTrue))]
            , sigPathCond   = []
            }
          goal = RBase "v" recordSort (PRel Ge (PMeasureApp "sel_quota" (PVar "v")) (PMeasureApp "sel_used" (PVar "v")))
          ctx = Context (Map.fromList [("r", recordSort), ("d", SortInt)])
          artifact = WakeStalkArtifact
            { wsaVertexId          = "adjustQuota"
            , wsaInputContext      = ctx
            , wsaFinalSig          = sig
            , wsaDisambiguatedGoal = goal
            , wsaVerifiedTerm      = termT1
            , wsaInventedSeps      = []
            , wsaZ3Refutations     = 3
            }
          polySchema = generalizeToOpenRowSchema artifact
      schemaTypeVars polySchema `shouldBe` ["rho_adjustQuota"]
      case schemaBody polySchema of
        RArrow "d" (RBScalar (RBase _ SortInt _)) (RArrow "r" (RBScalar (RBase _ genSort _)) (RBScalar retBase)) -> do
          case genSort of
            SortADT adtName [SortRecordRow (RowSchema fs), SortVar rho] -> do
              adtName `shouldBe` "RecordF_Tenant"
              Map.keys fs `shouldBe` ["quota", "used"]
              rho `shouldBe` "rho_adjustQuota"
            _ -> expectationFailure $ "Expected generalized open row sort, got: " ++ show genSort
          case rRefine retBase of
            PAnd conjuncts -> do
              let hasUsedFrame = any (\case
                    PRel Eq (PMeasureApp "sel_used" (PVar "v")) (PMeasureApp "sel_used" (PVar "r")) -> True
                    _ -> False) conjuncts
              hasUsedFrame `shouldBe` True
            _ -> expectationFailure "Expected PAnd refinement with frame conjuncts"
        _ -> expectationFailure $ "Expected nested RArrow schema, got: " ++ show (schemaBody polySchema)

    it "3. crystallizeStalkToCombinator encapsulates internal branch qualifiers" do
      let qualBoundary = Qualifier "Q_bound" [("v", recordSort)]
            (PRel Ge (PMeasureApp "sel_quota" (PVar "v")) (PMeasureApp "sel_used" (PVar "v")))
          qualInternal = Qualifier "Q_internal" [("r", recordSort), ("d", SortInt)]
            (PRel Ge (PBinOp Add (PMeasureApp "sel_quota" (PVar "r")) (PVar "d")) (PMeasureApp "sel_used" (PVar "r")))
          sigWithQuals = LiquidSig
            { sigSorts      = Set.empty
            , sigMeasures   = Map.fromList
                [ ("sel_quota", MeasureDecl "sel_quota" recordSort SortInt False)
                , ("sel_used",  MeasureDecl "sel_used"  recordSort SortInt False)
                ]
            , sigCtorAxioms = []
            , sigQualifiers = Set.fromList [qualBoundary, qualInternal]
            , sigEnv        = Map.fromList [("r", RBScalar (RBase "v" recordSort PTrue)), ("d", RBScalar (RBase "v" SortInt PTrue))]
            , sigPathCond   = []
            }
          goal = RBase "v" recordSort (PRel Ge (PMeasureApp "sel_quota" (PVar "v")) (PMeasureApp "sel_used" (PVar "v")))
          ctx = Context (Map.fromList [("r", recordSort), ("d", SortInt)])
          artifact = WakeStalkArtifact
            { wsaVertexId          = "adjustQuota"
            , wsaInputContext      = ctx
            , wsaFinalSig          = sigWithQuals
            , wsaDisambiguatedGoal = goal
            , wsaVerifiedTerm      = termT1
            , wsaInventedSeps      = []
            , wsaZ3Refutations     = 2
            }
          bank0 = PersistentLibraryBank Map.empty Map.empty IntMap.empty (\_ _ -> True)

      comb <- crystallizeStalkToCombinator Z3Hyperdoctrine bank0 artifact
      ccName comb `shouldBe` "cryst_adjustQuota"
      let outBasis = qbQualifiers (stepBasisOut (ccSymbolicStep comb))
      Set.member qualBoundary outBasis `shouldBe` True
      Set.member qualInternal outBasis `shouldBe` False

    it "4. runSleepPhaseCrystallization deduplicates structurally similar combinators and promotes high-gain measures" do
      let sig = LiquidSig
            { sigSorts      = Set.empty
            , sigMeasures   = Map.fromList
                [ ("sel_quota", MeasureDecl "sel_quota" recordSort SortInt False)
                , ("sel_used",  MeasureDecl "sel_used"  recordSort SortInt False)
                ]
            , sigCtorAxioms = []
            , sigQualifiers = Set.empty
            , sigEnv        = Map.fromList [("r", RBScalar (RBase "v" recordSort PTrue)), ("d", RBScalar (RBase "v" SortInt PTrue))]
            , sigPathCond   = []
            }
          goal = RBase "v" recordSort (PRel Ge (PMeasureApp "sel_quota" (PVar "v")) (PMeasureApp "sel_used" (PVar "v")))
          ctx = Context (Map.fromList [("r", recordSort), ("d", SortInt)])
          art1 = WakeStalkArtifact "stalk1" ctx sig goal termT1 [] 2
          art2 = WakeStalkArtifact "stalk2" ctx sig goal termT1 [] 2
          invMeasure = MeasureDecl "tag_count" SortInt SortInt False
          invAxiom = CtorMeasureAxiom "Nil" [] "tag_count" PTrue
          invQual = Qualifier "Q_tag" [("x", SortInt)] (PRel Ge (PVar "x") (PIntLit 0))
          sepResult = SeparatorSynthesisResult
            { sepNewMeasure = Just invMeasure
            , sepNewAxioms  = [invAxiom]
            , sepQualifier  = invQual
            }
          art3 = WakeStalkArtifact "stalk3" ctx sig goal termT1 [sepResult] 4
          bank0 = PersistentLibraryBank Map.empty Map.empty IntMap.empty (\_ _ -> True)

      bankFinal <- runSleepPhaseCrystallization Z3Hyperdoctrine 2.0 [art1, art2, art3] bank0
      Map.member "cryst_stalk1" (bankCombinators bankFinal) `shouldBe` True
      Map.member "tag_count" (bankPromotedMeas bankFinal) `shouldBe` True
      let promoted = bankPromotedMeas bankFinal Map.! "tag_count"
      mprUsageCount promoted `shouldBe` 1
      mprNetMdlGain promoted `shouldBe` 10.0

    it "5. injectLibraryIntoStalkSig enriches signatures with promoted library components" do
      let invMeasure = MeasureDecl "tag_count" SortInt SortInt False
          invAxiom = CtorMeasureAxiom "Nil" [] "tag_count" PTrue
          invQual = Qualifier "Q_tag" [("x", SortInt)] (PRel Ge (PVar "x") (PIntLit 0))
          rec = MeasurePromotionRecord invMeasure [invAxiom] invQual 1 10.0
          dummyStep = LiquidSymbolicStep "cryst_step" (Context Map.empty) (Context Map.empty)
                        (QualifierBasis Set.empty) (QualifierBasis Set.empty)
                        (QualifierConj Set.empty) (QualifierConj Set.empty) (FAtom PTrue)
          comb = CrystallizedCombinator "cryst_step" (RSchema [] (RBScalar (RBase "v" SortInt PTrue))) dummyStep (TIntLit 0) [] 10.0
          bank = PersistentLibraryBank
            { bankCombinators   = Map.singleton "cryst_step" comb
            , bankPromotedMeas  = Map.singleton "tag_count" rec
            , bankCanonicalBeam = IntMap.empty
            , bankEvalPred      = \_ _ -> True
            }
          sig0 = LiquidSig Set.empty Map.empty [] Set.empty Map.empty []
          (enrichedSig, enrichedComps, profunctorSteps) = injectLibraryIntoStalkSig bank sig0 Map.empty

      Map.member "tag_count" (sigMeasures enrichedSig) `shouldBe` True
      Set.member invQual (sigQualifiers enrichedSig) `shouldBe` True
      length (sigCtorAxioms enrichedSig) `shouldBe` 1
      Map.member "cryst_step" enrichedComps `shouldBe` True
      length profunctorSteps `shouldBe` 1

  describe "Gargamelle.Persistence.RewriteMining (Conditional DPO Law Synthesis)" do
    let recordSort = SortADT "RecordF_Tenant" [SortRecordRow (RowSchema (Map.fromList [("quota", SortInt), ("used", SortInt)])), SortVar "rho"]
        guardCond = PRel Ge (PBinOp Add (PMeasureApp "sel_quota" (PVar "r")) (PVar "d"))
                            (PMeasureApp "sel_used" (PVar "r"))
        termAdjust = TIf guardCond
                         (TApp (TVar "setF_quota") [TApp (TVar "add") [TApp (TVar "getF_quota") [TVar "r"], TVar "d"], TVar "r"])
                         (TApp (TVar "setF_quota") [TApp (TVar "getF_used") [TVar "r"], TVar "r"])
        ctxAdjust = Context (Map.fromList [("r", recordSort), ("d", SortInt)])
        outCtxAdjust = Context (Map.fromList [("v", recordSort)])
        dummyStep = LiquidSymbolicStep "cryst_adjustQuota" ctxAdjust outCtxAdjust
                      (QualifierBasis Set.empty) (QualifierBasis Set.empty)
                      (QualifierConj Set.empty) (QualifierConj Set.empty) (FAtom PTrue)
        combAdjust = CrystallizedCombinator
          { ccName            = "cryst_adjustQuota"
          , ccPolySchema      = RSchema ["rho"] (RArrow "d" (RBScalar (RBase "v" SortInt PTrue))
                                                  (RArrow "r" (RBScalar (RBase "v" recordSort PTrue))
                                                    (RBScalar (RBase "v" recordSort PTrue))))
          , ccSymbolicStep    = dummyStep
          , ccImplementation  = termAdjust
          , ccSemanticHash    = [True, False]
          , ccMdlSavingsScore = 5.0
          }
        evalPred mdl = \case
          PRel Ge (PBinOp Add (PMeasureApp "sel_quota" (PVar rVar)) (PVar argVar)) (PMeasureApp "sel_used" (PVar rVar2))
            | rVar == rVar2 ->
              let q = case Map.lookup rVar (modelVarEnv mdl) of
                        Just (VRecord m) -> case Map.lookup "quota" m of Just (VInt i) -> i; _ -> 0
                        _ -> 0
                  u = case Map.lookup rVar (modelVarEnv mdl) of
                        Just (VRecord m) -> case Map.lookup "used" m of Just (VInt i) -> i; _ -> 0
                        _ -> 0
                  argVal = case Map.lookup argVar (modelVarEnv mdl) of
                             Just (VInt i) -> i
                             _ -> 0
              in (q + argVal) >= u
          PRel Ge (PBinOp Add (PMeasureApp "sel_quota" (PVar rVar)) (PBinOp Add (PVar aVar) (PVar bVar))) (PMeasureApp "sel_used" (PVar rVar2))
            | rVar == rVar2 ->
              let q = case Map.lookup rVar (modelVarEnv mdl) of
                        Just (VRecord m) -> case Map.lookup "quota" m of Just (VInt i) -> i; _ -> 0
                        _ -> 0
                  u = case Map.lookup rVar (modelVarEnv mdl) of
                        Just (VRecord m) -> case Map.lookup "used" m of Just (VInt i) -> i; _ -> 0
                        _ -> 0
                  aVal = case Map.lookup aVar (modelVarEnv mdl) of
                           Just (VInt i) -> i
                           _ -> 0
                  bVal = case Map.lookup bVar (modelVarEnv mdl) of
                           Just (VInt i) -> i
                           _ -> 0
              in (q + (aVal + bVal)) >= u
          _ -> True

        -- Model 1: agrees on fusion (10 + 2 >= 4, 12 + 3 >= 4)
        m1 = LiquidModel
          { modelVarEnv = Map.fromList
              [ ("r", VRecord (Map.fromList [("quota", VInt 10), ("used", VInt 4)]))
              , ("a_arg", VInt 2)
              , ("b_arg", VInt 3)
              , ("d", VInt 2)
              ]
          , modelMeasureInterp = Map.empty
          , modelAbductSol     = Map.empty
          }
        -- Model 2: underflow branch where L and R differ (10 + (-8) = 2 < 4)
        m2 = LiquidModel
          { modelVarEnv = Map.fromList
              [ ("r", VRecord (Map.fromList [("quota", VInt 10), ("used", VInt 4)]))
              , ("a_arg", VInt (-8))
              , ("b_arg", VInt 5)
              , ("d", VInt (-8))
              ]
          , modelMeasureInterp = Map.empty
          , modelAbductSol     = Map.empty
          }
        beam = IntMap.fromList [(1, m1), (2, m2)]
        bank = PersistentLibraryBank
          { bankCombinators   = Map.singleton "cryst_adjustQuota" combAdjust
          , bankPromotedMeas  = Map.empty
          , bankCanonicalBeam = beam
          , bankEvalPred      = evalPred
          }

    it "1. enumerateCandidateMotifs discovers Idempotence, ScalarFusion, Cancellation, and Absorption motifs" do
      let motifs = enumerateCandidateMotifs bank
          names = map clsName motifs
          kinds = map clsMotif motifs
      names `shouldContain` ["DPO_Idemp_cryst_adjustQuota"]
      names `shouldContain` ["DPO_Fusion_cryst_adjustQuota"]
      names `shouldContain` ["DPO_Cancel_cryst_adjustQuota_cryst_adjustQuota"]
      names `shouldContain` ["DPO_Absorb_cryst_adjustQuota_cryst_adjustQuota"]
      kinds `shouldContain` [MotifIdempotence]
      kinds `shouldContain` [MotifScalarFusion]
      kinds `shouldContain` [MotifCancellation]
      kinds `shouldContain` [MotifAbsorption]

    it "2. computeBeamEqualityOverlap filters out incompatible pairs without calling SMT" do
      let motifs = enumerateCandidateMotifs bank
      case [ m | m <- motifs, clsMotif m == MotifScalarFusion ] of
        (fusionMotif : _) -> do
          let overlap = computeBeamEqualityOverlap bank fusionMotif
          IntSet.member 1 overlap `shouldBe` True
          IntSet.member 2 overlap `shouldBe` False
        [] -> expectationFailure "Expected MotifScalarFusion motif"

    it "3. cryst_adjustQuota fusion walkthrough (PDF p. 47) mines DPO_Fusion_cryst_adjustQuota" do
      let qualFusion = Qualifier "Q_fuse" [("r", recordSort), ("a_arg", SortInt)]
            (PRel Ge (PBinOp Add (PMeasureApp "sel_quota" (PVar "r")) (PVar "a_arg")) (PMeasureApp "sel_used" (PVar "r")))
          basis = QualifierBasis (Set.singleton qualFusion)
          sig = LiquidSig
            { sigSorts      = Set.empty
            , sigMeasures   = Map.fromList
                [ ("sel_quota", MeasureDecl "sel_quota" recordSort SortInt False)
                , ("sel_used",  MeasureDecl "sel_used"  recordSort SortInt False)
                ]
            , sigCtorAxioms = []
            , sigQualifiers = Set.singleton qualFusion
            , sigEnv        = Map.fromList [("r", RBScalar (RBase "v" recordSort PTrue))]
            , sigPathCond   = [PRel Ge (PMeasureApp "sel_quota" (PVar "r")) (PMeasureApp "sel_used" (PVar "r"))]
            }

      (laws, rules) <- mineConditionalDPORules Z3Hyperdoctrine Z3StreamSession sig basis 1 0.0 bank
      let fusionLaws = [ l | l <- laws, clsMotif (dclSchema l) == MotifScalarFusion ]
      case fusionLaws of
        (fusionLaw : _) -> do
          clsName (dclSchema fusionLaw) `shouldBe` "DPO_Fusion_cryst_adjustQuota"
          clsCostDelta (dclSchema fusionLaw) `shouldBe` (-2)
          Set.member (qualBody qualFusion) (qcConjuncts (dclAbductedGuard fusionLaw)) `shouldBe` True
        [] -> expectationFailure "Expected DPO_Fusion_cryst_adjustQuota to be discovered"

      -- Verify compiled DPO rule
      let fusionRules = [ r | r <- rules, dpoName r == "DPO_Fusion_cryst_adjustQuota" ]
      case fusionRules of
        (dpoRule : _) -> do
          dpoCostDelta dpoRule `shouldBe` (-2)

          -- Verify executable DPO rule matches redex and builds additive RHS in an e-graph
          let eg0 = emptyAbductiveEGraph (Context Map.empty) sig basis IntMap.empty (\_ _ -> True)
              (cidX, eg1) = upsertENode (EVar "r") eg0
              (cidA, eg2) = upsertENode (EIntLit 2) eg1
              (cidB, eg3) = upsertENode (EIntLit 3) eg2
              (cidInner, eg4) = upsertENode (EApp "cryst_adjustQuota" [cidX, cidA]) eg3
              (cidOuter, eg5) = upsertENode (EApp "cryst_adjustQuota" [cidInner, cidB]) eg4

              matches = dpoMatchLHS dpoRule cidOuter eg5
          case matches of
            ((subst, _lhsTerm, _rhsTerm) : _) -> do
              Map.lookup "r" subst `shouldBe` Just cidX
              Map.lookup "a_arg" subst `shouldBe` Just cidA
              Map.lookup "b_arg" subst `shouldBe` Just cidB

              let (cidRhs, eg6) = dpoRHSBuilder dpoRule subst eg5
              cidRhs `shouldNotBe` cidOuter
              case IntMap.lookup (unEClassId cidRhs) (egClasses eg6) of
                Nothing -> expectationFailure "Expected materialized RHS e-class"
                Just rhsEc -> do
                  let nodes = Set.toList (ecNodes rhsEc)
                  any (\case EApp "cryst_adjustQuota" [x, _sumNode] -> x == cidX; _ -> False) nodes `shouldBe` True
            [] -> expectationFailure "Expected match for cryst_adjustQuota redex"
        [] -> expectationFailure "Expected DPO rule for DPO_Fusion_cryst_adjustQuota"
