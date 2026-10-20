{-# LANGUAGE DataKinds #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE RankNTypes #-}

module Gargamelle.Logic.Signature
  ( Arity(..)
  , UniversalAlgebraSig(..)
  , LawvereSort(..)
  , LogicAST(..)
  , Entailment(..)
  ) where

import Data.Kind (Type)
import GHC.TypeLits (Nat)

-- | Promoted Arity kind for universal algebra signatures.
data Arity
  = Nullary
  | Unary
  | Binary
  | Nary Nat
  deriving (Eq, Show, Ord)

-- | Textbook Universal Algebra 4-tuple Signature promoted to a Kind via DataKinds.
data UniversalAlgebraSig = UASig
  { functions :: [(String, Arity)]
  , relations :: [(String, Arity)]
  , constants :: [String]
  } deriving (Eq, Show)

-- | Multi-sorted Lawvere theory sort signature mapping input product sorts to output sort.
data LawvereSort sort = LawvereOp [sort] sort
  deriving (Eq, Show)

-- | Observable deep embedding of First-Order Logic indexed by signature kind 'k'.
-- Avoids native (->) opacity so autonomous agents and SMT pipes can inspect,
-- serialize, and rewrite formulas.
data LogicAST (sig :: k) where
  LitTrue   :: LogicAST sig
  LitFalse  :: LogicAST sig
  AtomPred  :: String -> [String] -> LogicAST sig
  Not       :: LogicAST sig -> LogicAST sig
  And       :: LogicAST sig -> LogicAST sig -> LogicAST sig
  Or        :: LogicAST sig -> LogicAST sig -> LogicAST sig
  Implies   :: LogicAST sig -> LogicAST sig -> LogicAST sig
  Iff       :: LogicAST sig -> LogicAST sig -> LogicAST sig
  Forall    :: String -> LogicAST sig -> LogicAST sig
  Exists    :: String -> LogicAST sig -> LogicAST sig
  -- | Flat contiguous conjunction (prevents O(N^2) nested binary trees)
  FlatConj  :: [LogicAST sig] -> LogicAST sig
  -- | Flat variant disjunction
  FlatDisj  :: [LogicAST sig] -> LogicAST sig

deriving instance Show (LogicAST sig)
deriving instance Eq (LogicAST sig)

-- | Syntactic deductive entailment (⊢) independent of runtime execution.
class Entailment (sen :: k -> Type) where
  entails :: forall (sig :: k). [sen sig] -> sen sig -> Bool
