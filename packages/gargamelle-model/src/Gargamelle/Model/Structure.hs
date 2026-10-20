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

-- | Binds an interpreted symbol sort 's' to its runtime implementation 'interp s'
-- and formal specification 'pred s'.
class LogicModel interp pred s where
  evalSymbol :: interp s -> pred s -> Evidence

-- | Generic runtime model container holding named assignments or states.
newtype RuntimeModel val = RuntimeModel { getModelVal :: val }
  deriving (Eq, Show)

-- | Compose two verifiers over a pair/product model.
compilePairVerifier :: Verifier a -> Verifier b -> Verifier (a, b)
compilePairVerifier = divide id

-- | Compose two verifiers over a sum/variant model.
compileEitherVerifier :: Verifier a -> Verifier b -> Verifier (Either a b)
compileEitherVerifier = choose id
