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
import Gargamelle.Model.Satisfaction (verifyPredicate)
import Gargamelle.Logic.Defunctionalize (ObsMor(..))
import Propositional (PropSig(..), SentProp(..), ModProp(..))
import Gargamelle.Core.Institution.Liquid
import Gargamelle.Core.Institution.Liquid.Instance (checkSatisfactionCondition)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
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
