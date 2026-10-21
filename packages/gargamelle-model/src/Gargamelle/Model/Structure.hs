{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}

module Gargamelle.Model.Structure
  ( LogicModel(..)
  , RuntimeModel(..)
  , compilePairVerifier
  , compileEitherVerifier
  ) where

import Data.Functor.Contravariant.Divisible (divide, choose)
import Gargamelle.Model.Satisfaction (Evidence(..), Verifier)

{- Note [Universal LogicModel Sorting and Product Splittings]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-logic-model-sorting]
In categorical logic and universal algebra, a multi-sorted signature defines carriers
and operations across distinct sorts (types).

In Gargamelle:
  1. 'LogicModel interp pred s' binds an interpretation carrier ('interp s') to a specification
     predicate ('pred s') for a particular sort 's'. Evaluating a symbol under this pairing
     produces structured 'Evidence'.
  2. For composite system states represented as cartesian products (pairs '(a, b)'),
     'compilePairVerifier' decomposes the composite model using 'Divisible' ('divide id').
     Both components are verified, and any counterexamples are accumulated monoidally.
  3. For sum/variant models ('Either a b'), 'compileEitherVerifier' branches using
     'Decidable' ('choose id'), routing verification dynamically to the active case.

This ensures that model checking scales compositionally across structural products and sums
without monolithic verification functions.
-}

-- | Binds an interpreted symbol sort @s@ to its runtime implementation @interp s@
-- and formal specification @pred s@.
--
-- See Note [Universal LogicModel Sorting and Product Splittings] [ref:note-logic-model-sorting].
class LogicModel interp pred s where
  evalSymbol :: interp s -> pred s -> Evidence

-- | Generic runtime model container holding named assignments or states.
newtype RuntimeModel val = RuntimeModel { getModelVal :: val }
  deriving (Eq, Show)

-- | Compose two verifiers over a pair/product model.
--
-- See Note [Universal LogicModel Sorting and Product Splittings] [ref:note-logic-model-sorting].
compilePairVerifier :: Verifier a -> Verifier b -> Verifier (a, b)
compilePairVerifier = divide id

-- | Compose two verifiers over a sum/variant model.
compileEitherVerifier :: Verifier a -> Verifier b -> Verifier (Either a b)
compileEitherVerifier = choose id
