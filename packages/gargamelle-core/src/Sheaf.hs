{-# LANGUAGE DataKinds, TypeFamilies, GADTs, PolyKinds, FlexibleInstances, MultiParamTypeClasses #-}

module Sheaf where

import Institution
import Data.Proxy
import GHC.TypeLits (Symbol, KnownSymbol, symbolVal)
import qualified Data.Map as Map
import qualified Data.Set as Set

-- | A wrapper for sheaf signatures (lists of open sets?).
-- We keep it phantom for now.
newtype SheafSig (syms :: [Symbol]) = SheafSig (Proxy syms)

-- | Terms: we represent sections of a sheaf over an open set.
-- For simplicity, we use strings to represent sections.
data Term (syms :: [Symbol]) where
  Section :: KnownSymbol sym => Proxy sym -> Term syms
  -- We could add more constructors for restriction, etc.

-- | Sentences: we represent sheaf morphisms or logical formulas.
-- For now, we use equality of sections.
data SheafSentence (syms :: [Symbol]) where
  SectEq :: Term syms -> Term syms -> SheafSentence syms
  -- We could add more logical connectives.

-- | Model: a sheaf assignment to open sets.
-- We use a simple map from open set names (symbols) to sets of sections.
newtype SheafModel (syms :: [Symbol]) = SheafModel
  { sections :: Map.Map String (Set.Set String) -- open set -> set of section names
  }

instance Institution (SheafSig syms) where
  type Sentence (SheafSig syms) = SheafSentence syms
  type Model  (SheafSig syms)  = SheafModel syms
  satisfies _ m (SectEq t1 t2) = evalTerm m t1 == evalTerm m t2

evalTerm :: SheafModel syms -> Term syms -> String
evalTerm _ (Section s) = symbolVal s -- section evaluates to its name

-- Smart constructors
section :: KnownSymbol sym => Proxy sym -> Term syms
section = Section

sectEq :: Term syms -> Term syms -> SheafSentence syms
sectEq = SectEq
