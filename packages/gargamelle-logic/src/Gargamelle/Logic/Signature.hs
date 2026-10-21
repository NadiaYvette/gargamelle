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

{- Note [Flat Logic AST Representation]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-flat-logic-ast]
In formal verification, SMT piping, and sheaf-theoretic restriction solvers, formulas
frequently contain dozens or hundreds of simultaneous clauses (e.g., global state
invariants, cell complex boundary matchings, and frame conditions).

Representing large n-ary conjunctions as nested binary trees
  (And (And (And A B) C) D)
induces three severe performance penalties:
  1. O(N^2) recursive traversal cost for deep flattening and SMT-LIB2 syntax generation.
  2. High heap allocation from intermediate binary constructor nodes.
  3. GHC call-stack depth exhaustion on deeply nested formulas during pattern matching.

To eliminate this bottleneck, 'LogicAST' incorporates 'FlatConj' and 'FlatDisj' alongside
binary 'And' and 'Or'. 'FlatConj' stores clauses as a flat contiguous list of subformulas,
enabling O(N) linear serialization into SMT-LIB2 s-expressions, trivial constant folding
(pruning 'LitTrue' / 'LitFalse' in a single pass), and cache-friendly iteration.
-}

-- | Observable deep embedding of First-Order Logic indexed by signature kind @k@.
--
-- See Note [Flat Logic AST Representation] [ref:note-flat-logic-ast].
--
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
