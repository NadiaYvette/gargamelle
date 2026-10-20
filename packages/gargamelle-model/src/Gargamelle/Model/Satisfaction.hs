{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE RankNTypes #-}

module Gargamelle.Model.Satisfaction
  ( Evidence(..)
  , Verifier(..)
  , evalVerifier
  , inspectVerifierPlan
  , SatisfactionIso(..)
  , verifyPredicate
  ) where

import Data.Kind (Type)
import Data.Void (Void, absurd)
import Data.Functor.Contravariant (Contravariant(..))
import Data.Functor.Contravariant.Divisible (Divisible(..), Decidable(..))
import Gargamelle.Logic.Defunctionalize (ObsMor(..), evalObsMor, inspectObsMor)

-- | Observable V-Enriched Satisfaction Evidence (replaces opaque Bool).
-- Preserves structural counterexamples so autonomous agents do not repeat failed patches.
data Evidence
  = VerifiedSection
  | Counterexample
      { violatedSymbol :: String
      , witnessPayload :: String
      }
  deriving (Eq, Show)

-- | Evidence forms a Monoid where VerifiedSection is the identity and
-- Counterexamples accumulate across verification checks.
instance Semigroup Evidence where
  VerifiedSection <> e = e
  e <> VerifiedSection = e
  Counterexample s1 w1 <> Counterexample s2 w2 =
    Counterexample (s1 ++ "; " ++ s2) (w1 ++ " | " ++ w2)

instance Monoid Evidence where
  mempty = VerifiedSection

-- | Observable Free Divisible/Decidable Verifier AST.
-- Every product split, sum branch, and atomic check is a first-class constructor
-- that an AI agent or SMT pipe can inspect, optimize, or translate before execution.
data Verifier (model :: Type) where
  ConquerV   :: Verifier a
  LoseV      :: ObsMor a Void -> Verifier a
  AtomCheck  :: String -> (model -> Evidence) -> Verifier model
  ContramapV :: ObsMor a b -> Verifier b -> Verifier a
  DivideV    :: ObsMor a (b, c) -> Verifier b -> Verifier c -> Verifier a
  ChooseV    :: ObsMor a (Either b c) -> Verifier b -> Verifier c -> Verifier a

instance Contravariant Verifier where
  contramap f = ContramapV (SymbolicStep "contramap" f)

instance Divisible Verifier where
  conquer      = ConquerV
  divide split = DivideV (SymbolicStep "divide" split)

instance Decidable Verifier where
  lose f       = LoseV (SymbolicStep "lose" f)
  choose split = ChooseV (SymbolicStep "choose" split)

-- | Helper to create an atomic predicate verifier returning a Counterexample upon failure.
verifyPredicate :: String -> (model -> Bool) -> Verifier model
verifyPredicate name p = AtomCheck name $ \m ->
  if p m
    then VerifiedSection
    else Counterexample name ("Predicate violated: " ++ name)

-- | Execute the observable Verifier AST against a concrete runtime model.
evalVerifier :: Verifier model -> model -> Evidence
evalVerifier ConquerV _              = VerifiedSection
evalVerifier (LoseV f) m             = absurd (evalObsMor f m)
evalVerifier (AtomCheck _ check) m   = check m
evalVerifier (ContramapV f v) m      = evalVerifier v (evalObsMor f m)
evalVerifier (DivideV split vB vC) m =
  let (b, c) = evalObsMor split m
  in evalVerifier vB b <> evalVerifier vC c
evalVerifier (ChooseV split vB vC) m =
  either (evalVerifier vB) (evalVerifier vC) (evalObsMor split m)

-- | Static introspection: Extract all verification checks and morphism steps
-- embedded inside a Verifier without needing a runtime model.
inspectVerifierPlan :: Verifier model -> [String]
inspectVerifierPlan ConquerV          = ["Conquer"]
inspectVerifierPlan (LoseV f)         = "Lose" : inspectObsMor f
inspectVerifierPlan (AtomCheck sym _) = ["AtomCheck:" ++ sym]
inspectVerifierPlan (ContramapV f v)  = inspectObsMor f ++ inspectVerifierPlan v
inspectVerifierPlan (DivideV f vB vC) = inspectObsMor f ++ inspectVerifierPlan vB ++ inspectVerifierPlan vC
inspectVerifierPlan (ChooseV f vB vC) = inspectObsMor f ++ inspectVerifierPlan vB ++ inspectVerifierPlan vC

-- | Observable Witness of the Satisfaction Condition Equivalence (⟺):
-- Translates verification evidence forward and backward across a signature morphism.
data SatisfactionIso = SatisfactionIso
  { forwardEvidence  :: ObsMor Evidence Evidence
  , backwardEvidence :: ObsMor Evidence Evidence
  }
