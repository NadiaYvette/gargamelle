{-# LANGUAGE DataKinds, TypeFamilies, GADTs, PolyKinds, FlexibleInstances, MultiParamTypeClasses, BlockArguments #-}

module RefinementCalculus where

import Institution
import Data.Proxy
import GHC.TypeLits (Symbol)
import qualified FirstOrder as FO

-- | A wrapper for refinement calculus signatures (lists of variables?).
-- We keep it phantom for now.
newtype RCSig (syms :: [Symbol]) = RCSig (Proxy syms)

-- | Terms: we don't have terms in the refinement calculus language itself;
--   specifications are built from predicates (which are first-order formulas).
--   We reuse FirstOrder's term type for building predicates.
type Term (syms :: [Symbol]) = FO.Term

-- | Predicates: first-order formulas (we reuse FirstOrder's Formula GADT).
type Predicate (syms :: [Symbol]) = FO.Formula syms

-- | Specification: a pair of a precondition and a postcondition.
data Spec (syms :: [Symbol]) = Spec
  { pre :: Predicate syms
  , post :: Predicate syms
  }

-- | Sentences: refinement judgments.
data RCSentence (syms :: [Symbol]) where
  Refine :: Spec syms -> Spec syms -> RCSentence syms
  -- We could also add: Skip, Assign, Seq, etc., as in the refinement calculus.

-- | Model: a first-order model (we reuse FirstOrder's model).
type RCModel (syms :: [Symbol]) = FO.FOLModel syms

instance Institution (RCSig syms) where
  type Sentence (RCSig syms) = RCSentence syms
  type Model  (RCSig syms)  = RCModel syms
  satisfies _ m (Refine spec1 spec2) =
    let impl = FO.impl  -- implication from FirstOrder smart constructors
        pre1 = pre spec1
        pre2 = pre spec2
        post1 = post spec1
        post2 = post spec2
    in satisfies (Proxy :: Proxy (FO.FOLSig syms)) m (impl pre2 pre1) &&
       satisfies (Proxy :: Proxy (FO.FOLSig syms)) m (impl post1 post2)

-- | Smart constructors for specifications.
spec :: Predicate syms -> Predicate syms -> Spec syms
spec = Spec

-- | Smart constructors for refinement judgments.
refine :: Spec syms -> Spec syms -> RCSentence syms
refine = Refine
