{-# LANGUAGE DataKinds, TypeFamilies, GADTs, PolyKinds, TypeOperators, FlexibleInstances, MultiParamTypeClasses #-}

module Hyperdoctrine where

import Institution
import Data.Proxy
import GHC.TypeLits (Symbol, KnownSymbol, symbolVal)
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Folly.Formula as F
import qualified FirstOrder as FO

-- | A wrapper for hyperdoctrine signatures (lists of base types?).
-- We keep it phantom for now.
newtype HDCSig (syms :: [Symbol]) = HDCSig (Proxy syms)

-- | In a hyperdoctrine, we have a base category of contexts.
-- For simplicity, we represent contexts as lists of symbols (variables).
-- We don't actually build the category; we use it to index the fiber.
data Context (syms :: [Symbol]) where
  Nil  :: Context '[]   -- empty context
  Cons :: KnownSymbol sym => Proxy sym -> Context syms -> Context (sym ': syms)

-- | The fiber over a context: a poset of propositions (we reuse FirstOrder formulas).
-- In a real hyperdoctrine, this would be a Heyting algebra.
data Fiber (syms :: [Symbol]) where
  Prop :: KnownSymbol sym => Proxy sym -> Fiber syms
  -- We could add more: true, false, and, or, implies, etc., but we reuse FirstOrder for now.
  -- Actually, we want to reuse FirstOrder's Formula for the propositions.
  -- So we change: the fiber is actually the set of FirstOrder formulas over the context.
  -- But we need to account for the variables in the context.
  -- We'll instead use FirstOrder's Formula directly, but we need to know which variables are in scope.
  -- For simplicity, we'll say that the fiber formulas are built from the symbols in the context.
  -- We'll leave this as a placeholder and reuse FirstOrder's Formula with the understanding
  -- that the signature is the list of variables in the context.

-- | Actually, let's reuse FirstOrder's Formula for the fiber propositions.
--   The signature for the fiber is the list of variables (symbols) in the context.
--   So we need to convert a Context to a type-level list of symbols.
--   We'll do that with a type family.
--
--   However, note that Context is already indexed by [Symbol]. We can simply use the index.
--   We'll change the HDModel to take the list of symbols directly.
--
type family ContextToList (ctx :: [Symbol]) :: [Symbol] where
  ContextToList '[] = '[]
  ContextToList (x ': xs) = x ': ContextToList xs



-- | Model: a hyperdoctrine model consists of:
--   For each context, a first-order model (interpreting the variables as constants?).
--   Actually, in a hyperdoctrine, the models are assignments to the variables.
--   We'll reuse FirstOrder's model, but we need to parameterize by the list of symbols.
newtype HDModel (syms :: [Symbol]) = HDModel
  { foModel :: FO.FOLModel syms
  }

-- | Institution instance for the hyperdoctrine.
--   The signature is the context (as a phantom type).
--   We'll use the Context type as the signature kind.
instance Institution (HDCSig syms) where
  -- The sentences are the fibers over the empty context? Or over any context?
  -- In the Institution framework, the signature is fixed. We'll fix the signature to be the list of symbols.
  -- But we want to vary the context. We'll instead make the signature the context itself.
  -- However, the Institution class expects a fixed signature kind. We can use the Context type as the kind.
  -- We'll change: the signature is a Context (which is indexed by a list of symbols).
  -- We'll need to adjust the Instance to work with Context.
  -- Given time, we'll keep it simple and use the phantom signature as before, and leave the fiber as FirstOrder formulas.
  -- This is not a full hyperdoctrine but a placeholder.
  type Sentence (HDCSig syms) = FO.Formula syms
  type Model  (HDCSig syms)  = FO.FOLModel syms
  satisfies _ m s = case FO.evalFormula m Map.empty s of
                      Right b -> b
                      Left _  -> False

-- | Smart constructors for contexts.
nil :: Context '[]
nil = Nil

cons :: KnownSymbol sym => Proxy sym -> Context syms -> Context (sym ': syms)
cons = Cons
