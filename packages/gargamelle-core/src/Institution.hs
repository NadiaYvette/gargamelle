{-# LANGUAGE DataKinds #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeFamilies #-}

module Institution
  ( -- * Legacy Institution Interface
    Institution(..)
    -- * Modern Categorical Institution Architecture
  , module Gargamelle.Core.Institution
  , module Gargamelle.Core.Weaving
  , module Gargamelle.Core.Discovery
  , module Gargamelle.Core.Colimit
  ) where

import Data.Kind (Type)
import Data.Proxy
import Gargamelle.Core.Institution
import Gargamelle.Core.Weaving
import Gargamelle.Core.Discovery
import Gargamelle.Core.Colimit

-- | Legacy institution interface indexed by a signature type.
-- Provided for compatibility with legacy FirstOrder, Equational, and Propositional modules.
class Institution (sig :: Type) where
  -- | Sentences built over the signature.
  type Sentence sig :: Type

  -- | Models for the signature.
  type Model sig :: Type

  -- | Satisfaction relation: does a model make a sentence true?
  satisfies :: Proxy sig -> Model sig -> Sentence sig -> Bool