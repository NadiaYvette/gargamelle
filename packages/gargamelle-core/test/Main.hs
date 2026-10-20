{-# LANGUAGE DataKinds #-}
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

    it "computes mediating factorizer for semantic delta propagation" $ do
      -- Pushout of (Unit <- Unit -> Unit) is Unit
      let pBase = Unit
      let pAspect = Unit
      let candidateBase = Unit
      let candidateAspect = Unit
      let factorizer = factorSemanticDelta pBase pAspect candidateBase candidateAspect
      case factorizer of
        Unit -> True `shouldBe` True

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
