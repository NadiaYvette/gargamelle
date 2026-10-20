{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}

module Gargamelle.Logic.Galois
  ( Galois(..)
  , composeGalois
  , galoisObsMor
  ) where

import Data.Kind (Type)
import Control.Category (Category(..))
import Gargamelle.Logic.Defunctionalize (ObsMor(..))
import Prelude hiding (id, (.))

-- | Galois connection (restrict ⊣ coRestrict) between a Vertex Stalk and an Edge Stalk,
-- parameterized over the arrow category 'arr'.
data Galois (arr :: k -> k -> Type) vStalk eStalk = Galois
  { restrict   :: arr vStalk eStalk   -- ^ Lower adjoint α (projects specification to boundary)
  , coRestrict :: arr eStalk vStalk   -- ^ Upper adjoint γ (lifts boundary specification to vertex)
  }

-- | Compose two Galois connections in series.
composeGalois :: Category arr => Galois arr b c -> Galois arr a b -> Galois arr a c
composeGalois g2 g1 = Galois
  (restrict g2 . restrict g1)
  (coRestrict g1 . coRestrict g2)

-- | Construct an observable Galois connection from named projection/lifting functions.
galoisObsMor :: String -> (v -> e) -> (e -> v) -> Galois ObsMor v e
galoisObsMor label proj lift' = Galois
  (SymbolicStep (label ++ "-restrict") proj)
  (SymbolicStep (label ++ "-coRestrict") lift')
