{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}

-- | Milestone M2: Beam Persistence Strand
--
-- Lifts Beam database queries into first-class Kernmantle strands.
module Effect.Strand.Beam
  ( QueryBeam(..)
  ) where

import Effect.Strand (QueryBeam(..))
