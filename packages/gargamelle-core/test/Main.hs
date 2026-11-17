{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE StandaloneDeriving #-}

module Main (main) where

import Test.Hspec
import Proarrow.Core (CategoryOf(..), type (~>))
import Proarrow.Category.Instance.Bool (BOOL(..), Booleans(..))
import Proarrow.Category.Instance.Unit (Unit(..))
import Gargamelle.Core.Institution
import Gargamelle.Core.Weaving
import Gargamelle.Core.Discovery
import Gargamelle.Core.Colimit
import Gargamelle.Logic.Satisfaction (verifyPredicate)
import Gargamelle.Logic.Defunctionalize (ObsMor(..))
import Propositional (PropSig(..), SentProp(..), ModProp(..))
import Gargamelle.Core.Institution.Liquid
import Gargamelle.Core.Institution.Liquid.Instance (checkSatisfactionCondition)
import Gargamelle.Core.Institution.Liquid.Polytropos
import Gargamelle.Core.Institution.Liquid.Penelope
import Gargamelle.CodeGen.Haskell
import Gargamelle.CodeGen.OrganIR
import Gargamelle.HostVM.PgclPushout
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Institution as Legacy
import Data.Proxy (Proxy(..))
import GHC.TypeLits (symbolVal)

-- | A concrete minimal Categorical Institution over the thin category BOOL.
data TestInst

-- Sentences indexed by BOOL
data TestSen (b :: BOOL) where
  FlsSen :: String -> TestSen FLS
  TruSen :: String -> TestSen TRU

deriving instance Show (TestSen b)
deriving instance Eq (TestSen b)

-- Models indexed by BOOL
data TestMod (b :: BOOL) where
  FlsMod :: Int -> TestMod FLS
  TruMod :: Int -> TestMod TRU

deriving instance Show (TestMod b)
deriving instance Eq (TestMod b)

type instance Sig TestInst = BOOL

instance LogicalSyntax TestInst where
  type Sen TestInst = TestSen
  translateSen Fls (FlsSen s) = FlsSen s
  translateSen F2T (FlsSen s) = TruSen s
  translateSen Tru (TruSen s) = TruSen s
  (|-) _ _ = True

instance ModelTheory TestInst where
  type Mod TestInst = TestMod
  reductMod Fls = SymbolicStep "reductFls" id
  reductMod F2T = SymbolicStep "reductF2T" (\(TruMod n) -> FlsMod n)
  reductMod Tru = SymbolicStep "reductTru" id

instance CategoricalInstitution TestInst where
  satisfactionVerifier (FlsSen s) = verifyPredicate s (\(FlsMod n) -> n >= 0)
  satisfactionVerifier (TruSen s) = verifyPredicate s (\(TruMod n) -> n >= 0)

main :: IO ()
main = hspec $ do
  -- Tested against Note [Categorical Pushout Feature Weaving] [ref:note-pushout-feature-weaving]
  describe "Pushout Feature Weaving (B ⨿_C W)" $ do
    it "weaves aspect into base signature over a shared interface in Unit category" $ do
      let inclBase   = Unit
      let inclAspect = Unit
      weaveAspect inclBase inclAspect $ \injBase injAspect -> do
        case (injBase, injAspect) of
          (Unit, Unit) -> True `shouldBe` True

    it "weaves aspect into base signature over thin boolean category" $ do
      -- C = FLS, Base = FLS, Aspect = TRU
      let inclBase   = Fls :: FLS ~> FLS
      let inclAspect = F2T :: FLS ~> TRU
      weaveAspect inclBase inclAspect $ \(injBase :: FLS ~> p) (injAspect :: TRU ~> p) -> do
        -- By pushout of (FLS <- FLS -> TRU), the apex is TRU
        -- with injBase = F2T and injAspect = Tru
        case (injBase, injAspect) of
          (F2T, Tru) -> True `shouldBe` True
          _          -> expectationFailure "Unexpected pushout injection arrows"

    -- Tested against Note [Colimit Mediating Morphisms and Semantic Delta Propagation] [ref:note-colimit-semantic-delta]
    it "computes mediating factorizer for semantic delta propagation" $ do
      -- Pushout of (Unit <- Unit -> Unit) is Unit
      let pBase = Unit
      let pAspect = Unit
      let candidateBase = Unit
      let candidateAspect = Unit
      let factorizer = factorSemanticDelta pBase pAspect candidateBase candidateAspect
      case factorizer of
        Unit -> True `shouldBe` True

  -- Tested against Note [Pullback Interface Discovery] [ref:note-pullback-interface-discovery]
  describe "Pullback Interface Discovery (A ×_E B)" $ do
    it "discovers minimal interface in Unit category" $ do
      let f = Unit
      let g = Unit
      discoverInterface f g $ \projA projB -> do
        case (projA, projB) of
          (Unit, Unit) -> True `shouldBe` True

    it "factors candidate interfaces through the universal pullback" $ do
      let p1 = Unit
      let p2 = Unit
      let q1 = Unit
      let q2 = Unit
      case factorInterface p1 p2 q1 q2 of
        Unit -> True `shouldBe` True

  -- Tested against Note [Goguen-Burstall Categorical Institution Satisfaction Invariance] [ref:note-institution-satisfaction-invariance]
  describe "Goguen-Burstall Categorical Institution Satisfaction Invariance" $ do
    it "verifies satisfaction condition invariance across signature morphisms" $ do
      let phi = FlsSen "x_non_negative"
      let mPrime = TruMod 42
      let (evLHS, evRHS, isPreserved) = checkSatisfactionInvariance @TestInst F2T phi mPrime
      isPreserved `shouldBe` True
      evLHS `shouldBe` evRHS

    it "detects counterexample invariance across signature morphisms" $ do
      let phi = FlsSen "x_non_negative"
      let mInvalid = TruMod (-5)
      let (evLHS, evRHS, isPreserved) = checkSatisfactionInvariance @TestInst F2T phi mInvalid
      isPreserved `shouldBe` True
      evLHS `shouldBe` evRHS

  describe "Legacy Institution Compatibility" $ do
    it "evaluates propositional satisfaction relation" $ do
      let formula :: SentProp '["p", "q"]
          formula = Conj (Atom (Proxy @"p")) (Atom (Proxy @"q"))
      let model :: ModProp '["p", "q"]
          model = ModProp (\p -> case symbolVal p of
            "p" -> True
            "q" -> True
            _   -> False)
      Legacy.satisfies (Proxy @(PropSig '["p", "q"])) model formula `shouldBe` True
      let badModel :: ModProp '["p", "q"]
          badModel = ModProp (\p -> case symbolVal p of
            "p" -> True
            "q" -> False
            _   -> False)
      Legacy.satisfies (Proxy @(PropSig '["p", "q"])) badModel formula `shouldBe` False

  describe "Liquid Institution & Satisfaction Condition" $ do
    it "verifies checkSatisfactionCondition holds invariant across signature morphisms for subtyping" $ do
      let sig1 = LiquidSig
            { sigSorts = Set.singleton "Int"
            , sigMeasures = Map.empty
            , sigCtorAxioms = []
            , sigQualifiers = Set.empty
            , sigEnv = Map.singleton "x" (RBScalar (RBase "v" SortInt (PRel Gt (PVar "v") (PIntLit 0))))
            , sigPathCond = []
            }
          sig2 = LiquidSig
            { sigSorts = Set.singleton "Int"
            , sigMeasures = Map.empty
            , sigCtorAxioms = []
            , sigQualifiers = Set.empty
            , sigEnv = Map.singleton "y" (RBScalar (RBase "v" SortInt (PRel Gt (PVar "v") (PIntLit 0))))
            , sigPathCond = []
            }
          sigma = LiquidSigMorphism
            { morphSource = sig1
            , morphTarget = sig2
            , morphSortMap = Map.empty
            , morphVarMap = Map.singleton "x" "y"
            , morphMeasMap = Map.empty
            }
          m2 = LiquidModel
            { modelVarEnv = Map.singleton "y" (VInt 5)
            , modelMeasureInterp = Map.empty
            , modelAbductSol = Map.empty
            }
          phi = SenSubtype
            { subValueVar = "v"
            , subSort = SortInt
            , subLhs = PRel Gt (PVar "x") (PIntLit 0)
            , subRhs = PRel Ge (PVar "x") (PIntLit 0)
            }
      checkSatisfactionCondition sigma m2 phi `shouldBe` True

    it "verifies checkSatisfactionCondition holds invariant for termination obligations" $ do
      let sig1 = LiquidSig mempty mempty [] mempty mempty []
          sig2 = LiquidSig mempty mempty [] mempty mempty []
          sigma = LiquidSigMorphism
            { morphSource = sig1
            , morphTarget = sig2
            , morphSortMap = Map.empty
            , morphVarMap = Map.empty
            , morphMeasMap = Map.singleton "len" "size"
            }
          m2 = LiquidModel
            { modelVarEnv = Map.empty
            , modelMeasureInterp = Map.fromList
                [ (("size", VInt 1), VInt 1)
                , (("size", VInt 2), VInt 2)
                ]
            , modelAbductSol = Map.empty
            }
          phi = SenTermination
            { termMeasure = "len"
            , termRecursiveArg = PIntLit 1
            , termInitialParam = PIntLit 2
            }
      checkSatisfactionCondition sigma m2 phi `shouldBe` True

  describe "Polytropos Open Rows & Measures" $ do
    let recRow = OpenRow
          { rowFields = Map.fromList [("x", SortInt), ("flag", SortBool)]
          , rowTail   = Just "rho"
          , rowLacks  = Set.singleton "z"
          }
        foldSpec = MonoidFoldSpec
          { foldMeasureName = "rowWeight"
          , foldSlotWeight  = "slotWeight"
          , foldZero        = 0
          , foldCombine     = Add
          }
        emptySig = LiquidSig
          { sigSorts      = Set.empty
          , sigMeasures   = Map.empty
          , sigCtorAxioms = []
          , sigQualifiers = Set.empty
          , sigEnv        = Map.empty
          , sigPathCond   = []
          }

    it "registers record row measures, McCarthy frame axioms, and fold axioms" $ do
      let sig = registerRecordRowMeasures "Point" recRow (Just foldSpec) emptySig
      -- Verify measures
      Map.member "sel_x" (sigMeasures sig) `shouldBe` True
      Map.member "sel_flag" (sigMeasures sig) `shouldBe` True
      Map.member "rowWeight" (sigMeasures sig) `shouldBe` True

      -- Verify axioms exist (sel_x hit + miss + fold)
      length (sigCtorAxioms sig) `shouldBe` 6

      -- Verify qualifiers
      Set.member "Point" (sigSorts sig) `shouldBe` True
      Set.size (sigQualifiers sig) `shouldBe` 3

    it "generates Polytropos record combinators" $ do
      let combs = polyRecordCombinators recRow
      Map.member "getF_x" combs `shouldBe` True
      Map.member "setF_x" combs `shouldBe` True
      Map.member "getF_flag" combs `shouldBe` True
      Map.member "setF_flag" combs `shouldBe` True

    it "registers variant row measures, payload measures, and tag qualifiers" $ do
      let varRow = OpenRow
            { rowFields = Map.fromList [("LeftVal", SortInt), ("RightVal", SortBool)]
            , rowTail   = Nothing
            , rowLacks  = Set.empty
            }
          sig = registerVariantRowMeasures "EitherVal" varRow emptySig
      Map.member "vtags" (sigMeasures sig) `shouldBe` True
      Map.member "vpayload_LeftVal" (sigMeasures sig) `shouldBe` True
      Map.member "vpayload_RightVal" (sigMeasures sig) `shouldBe` True
      length (sigCtorAxioms sig) `shouldBe` 4
      Set.size (sigQualifiers sig) `shouldBe` 2

    it "generates Polytropos variant combinators" $ do
      let varRow = OpenRow
            { rowFields = Map.fromList [("Ok", SortInt), ("Err", SortInt)]
            , rowTail   = Nothing
            , rowLacks  = Set.empty
            }
          combs = polyVariantCombinators varRow
      Map.member "absurdVariantF" combs `shouldBe` True
      Map.member "injF_Ok" combs `shouldBe` True
      Map.member "matchTagF_Ok" combs `shouldBe` True
      Map.member "narrowOutTagF_Ok" combs `shouldBe` True

    it "instantiates row tail morphisms correctly" $ do
      let srcSig = emptySig
            { sigSorts = Set.singleton "rho"
            , sigEnv   = Map.singleton "r" (RBScalar (RBase "v" (SortVar "rho") PTrue))
            }
          tgtRow = OpenRow
            { rowFields = Map.fromList [("x", SortInt), ("y", SortInt)]
            , rowTail   = Nothing
            , rowLacks  = Set.empty
            }
          tgtSig = emptySig
            { sigSorts = Set.fromList ["Point", "rho"]
            , sigEnv   = Map.singleton "r" (RBScalar (RBase "v" (SortRecordRow (RowSchema (rowFields tgtRow))) PTrue))
            }
          mor = instantiateRowTailMorphism "rho" tgtRow srcSig tgtSig
      Map.lookup "rho" (morphSortMap mor) `shouldBe` Just (SortRecordRow (RowSchema (rowFields tgtRow)))
      Map.lookup "r" (morphVarMap mor) `shouldBe` Just "r"

  describe "Penelope Effect Rows & Combinators" $ do
    let effRow = EffectRow
          { effList  = ["State", "Console"]
          , effTail  = Just "es"
          , effLacks = Set.empty
          }
        getOp = EffectType
          { effOpName     = "get"
          , effOpParams   = []
          , effOpResult   = SortInt
          , effOpPreCond  = PTrue
          , effOpPostCond = PRel Eq (PVar "v_res") (PVar "v_res")
          }
        putOp = EffectType
          { effOpName     = "put"
          , effOpParams   = [("s", SortInt)]
          , effOpResult   = SortADT "Unit" []
          , effOpPreCond  = PTrue
          , effOpPostCond = PTrue
          }
        emptySig = LiquidSig mempty mempty [] mempty mempty []

    it "registers effect signatures and budget qualifiers" $ do
      let sig = registerEffectSignatures effRow [getOp, putOp] (Just "fuel") emptySig
      Map.member "pre_get" (sigMeasures sig) `shouldBe` True
      Map.member "post_get" (sigMeasures sig) `shouldBe` True
      Map.member "pre_put" (sigMeasures sig) `shouldBe` True
      Map.member "post_put" (sigMeasures sig) `shouldBe` True
      Map.member "fuel" (sigMeasures sig) `shouldBe` True
      Set.member "State" (sigSorts sig) `shouldBe` True
      Set.member "Console" (sigSorts sig) `shouldBe` True
      -- 2 budget qualifiers + 2 op qualifiers = 4 qualifiers
      Set.size (sigQualifiers sig) `shouldBe` 4

    it "generates Penelope perform and handle effect combinators" $ do
      let combs = penelopeEffectCombinators effRow [getOp, putOp]
      Map.member "perform_get" combs `shouldBe` True
      Map.member "handle_get" combs `shouldBe` True
      Map.member "perform_put" combs `shouldBe` True
      Map.member "handle_put" combs `shouldBe` True

  describe "Gargamelle.CodeGen.Haskell (Zero-Cost Haskell Lowering)" $ do
    let guardCond = PRel Ge (PBinOp Add (PMeasureApp "sel_quota" (PVar "r")) (PVar "d"))
                            (PMeasureApp "sel_used" (PVar "r"))
        termAdjust = TIf guardCond
                         (TApp (TVar "setF_quota") [TApp (TVar "add") [TApp (TVar "getF_quota") [TVar "r"], TVar "d"], TVar "r"])
                         (TApp (TVar "setF_quota") [TApp (TVar "getF_used") [TVar "r"], TVar "r"])
        termEffect = TEffBind "res" (TApp (TVar "perform_AuditLog") [TVar "d"])
                       (TEffPure (TVar "res"))

    it "1. lowerSynTermToHaskell lowers Polytropos row and Penelope effect operations" $ do
      let hsCode = lowerSynTermToHaskell termAdjust
      T.isInfixOf "Polytropos.getF @\"quota\" r" hsCode `shouldBe` True
      T.isInfixOf "Polytropos.setF @\"quota\"" hsCode `shouldBe` True
      T.isInfixOf "Polytropos.getF @\"used\" r" hsCode `shouldBe` True
      T.isInfixOf "if" hsCode `shouldBe` True

      let hsEff = lowerSynTermToHaskell termEffect
      T.isInfixOf "Penelope.perform @AuditLog d" hsEff `shouldBe` True
      T.isInfixOf "pure (res)" hsEff `shouldBe` True

    it "2. generateModule generates complete Haskell module" $ do
      let modText = generateModule "Generated.QuotaPipeline" "adjustQuota" termAdjust
      T.isInfixOf "module Generated.QuotaPipeline where" modText `shouldBe` True
      T.isInfixOf "import qualified Polytropos" modText `shouldBe` True
      T.isInfixOf "import qualified Penelope" modText `shouldBe` True
      T.isInfixOf "adjustQuota :: _" modText `shouldBe` True
      T.isInfixOf "adjustQuota =" modText `shouldBe` True

  describe "Gargamelle.CodeGen.OrganIR (Dual-Backend MLIR & GIMPLE SSA)" $ do
    let recRow = OpenRow
          { rowFields = Map.fromList [("quota", SortInt), ("used", SortInt)]
          , rowTail   = Just "rho_r"
          , rowLacks  = Set.empty
          }
        rowDesc = buildRowLayoutDescriptor recRow
        effRow = EffectRow
          { effList  = ["AuditLog"]
          , effTail  = Nothing
          , effLacks = Set.empty
          }
        effDesc = buildEffectVectorDescriptor (\_ -> TailResumptive) effRow
        recordSort = SortADT "RecordF_Tenant" [SortRecordRow (RowSchema (rowFields recRow)), SortVar "rho_r"]
        sig = LiquidSig
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
          , sigPathCond   = [PRel Ge (PMeasureApp "sel_quota" (PVar "r")) (PMeasureApp "sel_used" (PVar "r"))]
          }
        goalBase = RBase "v" recordSort (PRel Ge (PMeasureApp "sel_quota" (PVar "v")) (PMeasureApp "sel_used" (PVar "v")))
        guardCond = PRel Ge (PBinOp Add (PMeasureApp "sel_quota" (PVar "r")) (PVar "d"))
                            (PMeasureApp "sel_used" (PVar "r"))
        termAdjust = TIf guardCond
                         (TApp (TVar "setF_quota") [TApp (TVar "add") [TApp (TVar "getF_quota") [TVar "r"], TVar "d"], TVar "r"])
                         (TApp (TVar "setF_quota") [TApp (TVar "getF_used") [TVar "r"], TVar "r"])

    it "1. lowerStalkToOrganProc lowers SynTerm into structured SSA with StmtAssume optimizer hints" $ do
      let proc = lowerStalkToOrganProc "adjustQuota" rowDesc effDesc sig goalBase termAdjust
      procName proc `shouldBe` "adjustQuota"
      let assumes = [ s | s@(StmtAssume _ _) <- procBody proc ]
      assumes `shouldNotSatisfy` null
      let ifStmts = [ s | s@(StmtIf {}) <- procBody proc ]
      ifStmts `shouldNotSatisfy` null

    it "2. emitMLIRProc produces valid MLIR func.func with organ.rep and scf.if constructs" $ do
      let proc = lowerStalkToOrganProc "adjustQuota" rowDesc effDesc sig goalBase termAdjust
          mlirText = emitMLIRProc proc
      T.isInfixOf "func.func @adjustQuota(" mlirText `shouldBe` True
      T.isInfixOf "!organ.eff_vec<1>" mlirText `shouldBe` True
      T.isInfixOf "!organ.rep<2>" mlirText `shouldBe` True
      T.isInfixOf "llvm.intr.assume" mlirText `shouldBe` True
      T.isInfixOf "scf.if" mlirText `shouldBe` True
      T.isInfixOf "organ.rep.slot_load" mlirText `shouldBe` True
      T.isInfixOf "organ.rep.slot_update" mlirText `shouldBe` True
      T.isInfixOf "func.return" mlirText `shouldBe` True

    it "3. emitGimpleProc produces valid GCC -fgimple SSA with basic blocks and __PHI nodes" $ do
      let proc = lowerStalkToOrganProc "adjustQuota" rowDesc effDesc sig goalBase termAdjust
          gimpleText = emitGimpleProc proc
      T.isInfixOf "struct PolytroposRep * __GIMPLE (ssa)" gimpleText `shouldBe` True
      T.isInfixOf "adjustQuota (" gimpleText `shouldBe` True
      T.isInfixOf "__BB(2):" gimpleText `shouldBe` True
      T.isInfixOf "__builtin_unreachable ();" gimpleText `shouldBe` True
      T.isInfixOf "r->slots[0]" gimpleText `shouldBe` True
      T.isInfixOf "__organ_rep_update" gimpleText `shouldBe` True
      T.isInfixOf "__PHI (" gimpleText `shouldBe` True
      T.isInfixOf "return" gimpleText `shouldBe` True

    describe "Gargamelle.HostVM.PgclPushout (Multi-OS Shim Categorical Pushout)" $ do
      it "sweeps all 5 target kernels (Linux, FreeBSD, illumos, seL4, Zircon)" $ do
        case sweepAllTargetKernels of
          Left err -> expectationFailure ("Expected successful kernel sweep, got error: " ++ show err)
          Right shims -> do
            length shims `shouldBe` 5
            let kernels = map sksKernel shims
            kernels `shouldBe` [KernelLinux, KernelFreeBSD, KernelIllumos, KernelSeL4, KernelZircon]
            all (T.isInfixOf "struct PolytroposRep" . sksProfunctorFunnelH) shims `shouldBe` True
