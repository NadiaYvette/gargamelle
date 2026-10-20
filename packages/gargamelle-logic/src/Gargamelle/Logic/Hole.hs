module Gargamelle.Logic.Hole
  ( HoleSpec(..)
  , mkHoleSpec
  ) where

-- | Contextual Hole E[□_τ] carrying its expected Assume-Guarantee contract
-- and unparsed gangue text for resilient parsing ("stope and winze" architecture).
data HoleSpec contract = HoleSpec
  { holeSpan     :: (Int, Int)
  , rawGangue    :: String
  , holeContract :: contract
  } deriving (Eq, Show)

-- | Smart constructor for HoleSpec.
mkHoleSpec :: (Int, Int) -> String -> contract -> HoleSpec contract
mkHoleSpec = HoleSpec
