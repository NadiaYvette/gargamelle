{-# LANGUAGE DataKinds, PolyKinds, KindSignatures, TypeFamilies #-}

module Institution where

import Data.Kind (Type)
import Data.Proxy
import GHC.TypeLits (Symbol)

-- | An institution is indexed by a signature (here, a type‑level list of Symbols).
-- The class provides the associated sentence and model types, and satisfaction.
class Institution (sig :: [Symbol]) where
  -- | Sentences built over the signature.
  type Sentence sig :: Type

  -- | Models for the signature.
  type Model  sig :: Type

  -- | Satisfaction relation: does a model make a sentence true?
  satisfies :: Proxy sig -> Model sig -> Sentence sig -> Bool