{-# LANGUAGE DataKinds, TypeFamilies, GADTs, KindSignatures, PolyKinds, TypeOperators, FlexibleInstances, MultiParamTypeClasses, GeneralizedNewtypeDeriving, DerivingStrategies #-}

module Evidence where

import Institution
import Data.Proxy
import Data.Hashable
import qualified Data.HashMap.Strict as HM
import Data.Maybe
import qualified TreeSitter as TS
import System.IO.Unsafe (unsafePerformIO)

-- | A structural representation of a code change or experiment that can be stored as evidence.
--   We store the string representation of the root node of the TreeSitter Tree,
--   computed via unsafePerformIO. This allows Eq, Show, and Hashable to be pure.
newtype StructuralRep = StructuralRep { getStructuralRep :: String }
  deriving stock (Eq, Show)

instance Hashable StructuralRep where
  hashWithSalt s (StructuralRep str) = hashWithSalt s str

-- | The type of failure reason (e.g., type error, divergence, missing instance).
data FailureReason
  = TypeError String
  | Divergence
  | MissingInstance String
  | OtherReason String
  deriving (Eq, Show)

-- | A single piece of evidence: a failed change and why it failed.
data Evidence sig = Evidence
  { evidenceChange   :: StructuralRep  -- ^ The structural representation of the change that failed
  , evidenceReason   :: FailureReason   -- ^ Why the change failed
  , evidenceContext  :: Proxy sig       -- ^ The signature (institution) this evidence belongs to
  }
  deriving (Eq, Show)

-- | A collection of evidence for a given signature, stored as a hash map for quick lookup.
newtype EvidenceStore sig = EvidenceStore
  { unEvidenceStore :: HM.HashMap StructuralRep (Evidence sig)
  } deriving (Eq, Show)

instance Semigroup (EvidenceStore sig) where
  EvidenceStore a <> EvidenceStore b = EvidenceStore (HM.union a b)

instance Monoid (EvidenceStore sig) where
  mempty = EvidenceStore HM.empty

-- | Create an empty evidence store.
emptyEvidenceStore :: EvidenceStore sig
emptyEvidenceStore = EvidenceStore HM.empty

-- | Add a piece of evidence to the store.
addEvidence :: Evidence sig -> EvidenceStore sig -> EvidenceStore sig
addEvidence e (EvidenceStore store) =
  EvidenceStore (HM.insert (evidenceChange e) e store)

-- | Check if a proposed change matches any known evidence (i.e., we have seen this exact structural rep fail).
--   In a more advanced version, we would use tree-diff to check for structural similarity.
proposesKnownFailure :: StructuralRep -> EvidenceStore sig -> Bool
proposesKnownFailure rep (EvidenceStore store) = HM.member rep store

-- | Retrieve the evidence for a given structural representation, if it exists.
getEvidence :: StructuralRep -> EvidenceStore sig -> Maybe (Evidence sig)
getEvidence rep (EvidenceStore store) = HM.lookup rep store

-- | Given a proposal (as a StructuralRep) and an evidence store, decide whether to allow the proposal.
--   Returns Nothing if the proposal is safe (no known failure), or Just the conflicting evidence if it is known to fail.
checkProposal :: StructuralRep -> EvidenceStore sig -> Maybe (Evidence sig)
checkProposal rep store
  | proposesKnownFailure rep store = getEvidence rep store
  | otherwise = Nothing

-- | Example usage: suppose we have a function that proposes a change and returns its structural rep.
--   In practice, this would be generated from the actual code change via tree-sitter.
class ToStructuralRep a where
  toStructuralRep :: a -> StructuralRep

-- | A wrapper for proposing a change in the context of an institution.
proposeChange :: (Institution sig, ToStructuralRep a) => a -> Proxy sig -> EvidenceStore sig -> Either (Evidence sig) a
proposeChange change sig store =
  case checkProposal (toStructuralRep change) store of
    Just ev -> Left ev
    Nothing -> Right change

-- | After attempting a change (e.g., building/testing), if it fails, we can record the evidence.
recordFailure :: (Institution sig, ToStructuralRep a) => a -> FailureReason -> Proxy sig -> EvidenceStore sig -> EvidenceStore sig
recordFailure change reason sig store =
  addEvidence (Evidence (toStructuralRep change) reason sig) store

-- | A simple instance for TS.Tree (for sketching purposes).
--   We compute the string representation of the root node via unsafePerformIO.
instance ToStructuralRep TS.Tree where
  toStructuralRep t = StructuralRep $ unsafePerformIO $ do
    rootNode <- TS.treeRootNode t
    TS.showNodeAsString rootNode