{-# LANGUAGE DataKinds, TypeFamilies, GADTs, PolyKinds, FlexibleInstances, MultiParamTypeClasses, DerivingStrategies #-}

module Evidence where

import Institution
import Data.Proxy
import Data.Hashable
import qualified Data.HashMap.Strict as HM
import qualified TreeSitter as TS
import Data.TreeDiff.Tree (treeDiff, EditTree(..), Edit(..))
import System.IO.Unsafe (unsafePerformIO)
import Data.Tree (Tree(..))

-- | A structural representation of a code change or experiment that can be stored as evidence.
--   We store the Data.Tree (converted from TreeSitter) and its root label string for equality and hashing.
data StructuralRep = StructuralRep { getRepString :: String, getDataTree :: Tree String }
  deriving (Eq, Show)

instance Hashable StructuralRep where
  hashWithSalt s (StructuralRep str _) = hashWithSalt s str

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

{- Note [Structural AST Change Tracking via Tree-Diff]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-structural-tree-diff]
In autonomous program repair, AI-guided synthesis, and Counterexample-Guided Inductive
Synthesis (CEGIS), recording failed patches as raw text strings or line-based unified diffs
fails for two fundamental reasons:
  1. False Negatives: An autonomous model will frequently propose patches with trivial
     syntactic variations (whitespace differences, identifier renaming, comment alterations)
     that produce distinct git diff hashes while representing the exact same failing AST.
  2. Unnecessary Sandboxing Overhead: Spawning container namespaces (/usr/bin/bwrap) and
     running full compiler toolchains (GHC) to evaluate a patch that is structurally
     identical to an already known failure wastes enormous amounts of energy and time.

'gargamelle-evidence' solves this by lifting patch tracking into structural AST space:
  - 'StructuralRep' wraps a 'Data.Tree String' converted from a Tree-Sitter concrete syntax tree.
  - 'EvidenceStore' maintains an exact hash index of previously failed structural representations,
    permitting O(1) membership testing via 'proposesKnownFailure'.
  - 'proposesSimilarFailure' runs 'treeDiff' to compute structural tree edit distance
    (accounting for insertions, deletions, and node swaps). If a proposed AST is within a
    configurable edit distance (e.g., <= 2) of a known failure, the proposal is rejected
    immediately without compiling or executing it.
-}

-- | A collection of evidence for a given signature, stored as a hash map for quick lookup.
--
-- See Note [Structural AST Change Tracking via Tree-Diff] [ref:note-structural-tree-diff].
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
proposeChange change _sig store =
  case checkProposal (toStructuralRep change) store of
    Just ev -> Left ev
    Nothing -> Right change

-- | After attempting a change (e.g., building/testing), if it fails, we can record the evidence.
recordFailure :: (Institution sig, ToStructuralRep a) => a -> FailureReason -> Proxy sig -> EvidenceStore sig -> EvidenceStore sig
recordFailure change reason sig =
  addEvidence (Evidence (toStructuralRep change) reason sig)

-- | Levenshtein distance algorithm for strings (kept for reference, not used in similarity checking now).
levenshtein :: String -> String -> Int
levenshtein [] ys = length ys
levenshtein xs [] = length xs
levenshtein (x:xs) (y:ys) = minimum [ levenshtein xs ys + if x == y then 0 else 1
                                    , levenshtein xs (y:ys) + 1
                                    , levenshtein (x:xs) ys + 1 ]

-- | Compute the edit distance from an Edit (EditTree a) (number of Ins, Del, Swp operations).
editDistance :: Edit (EditTree a) -> Int
editDistance = go
  where
    go (Cpy sub) = editDistanceTree sub
    go (Ins sub) = 1 + editDistanceTree sub
    go (Del sub) = 1 + editDistanceTree sub
    go (Swp l r) = 2 + editDistanceTree l + editDistanceTree r
    editDistanceTree (EditNode _ edits) = sum (map go edits)

-- | Convert a TS.Tree to a Data.Tree.Tree String by traversing the tree and converting each node to its string representation.
tsTreeToDataTree :: TS.Tree -> Tree String
tsTreeToDataTree tree = 
  let rootNode = unsafePerformIO $ TS.treeRootNode tree
  in tsNodeToDataTree rootNode
  where
    tsNodeToDataTree :: TS.Node -> Tree String
    tsNodeToDataTree node = 
      let label' = unsafePerformIO $ TS.showNodeAsString node
          childCount' = unsafePerformIO $ TS.nodeChildCount node
          count :: Int
          count = fromIntegral childCount'
      in  Node label' [ tsNodeToDataTree (unsafePerformIO $ TS.nodeChild node (fromIntegral i)) | i <- [0 .. count - 1] ]

-- | Extract the root label from a Data.Tree.Tree String.
getDataTreeRootLabel :: Tree String -> String
getDataTreeRootLabel (Node label _) = label

-- | A simple instance for TS.Tree (for sketching purposes).
--   We convert the TS.Tree to a Data.Tree.Tree String and set the string representation to the root label.
instance ToStructuralRep TS.Tree where
  toStructuralRep t = 
    let dt = tsTreeToDataTree t
        lbl = getDataTreeRootLabel dt
    in StructuralRep lbl dt

-- | Check if a proposed tree is structurally similar to any known failure in the evidence store.
--
-- See Note [Structural AST Change Tracking via Tree-Diff] [ref:note-structural-tree-diff].
--
-- Uses tree-diff to compute the edit distance on the Data.Tree representations and returns the evidence if the distance is <= similarityThreshold.
proposesSimilarFailure :: TS.Tree -> EvidenceStore sig -> Maybe (Evidence sig)
proposesSimilarFailure proposedTree (EvidenceStore store) =
  let threshold = 2 :: Int
      proposedDT = tsTreeToDataTree proposedTree
      found = foldr (\(evRep, ev) acc -> 
                     case acc of
                       Just _ -> acc  -- Already found a match, keep it
                       Nothing -> 
                         let evTree = getDataTree evRep
                             diff = treeDiff proposedDT evTree
                             dist = editDistance diff
                         in if dist <= threshold
                            then Just ev
                            else Nothing) 
                     Nothing 
                     (HM.toList store)
  in found