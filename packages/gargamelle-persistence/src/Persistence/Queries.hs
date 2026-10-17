-- | Milestone M2: Pure and Monadic Beam Queries for Evidence, Counterexamples, and Runs.
module Persistence.Queries
  ( -- * Evidence Queries
    insertEvidenceRecord
  , findEvidenceByRep
  , listAllEvidence
    -- * Counterexample Queries
  , insertCounterexample
  , findCounterexamplesFor
    -- * Run Queries
  , startRunRecord
  , completeRunRecord
  ) where

import Persistence.Beam
