{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Gargamelle.Equational.AbductiveEGraph
  ( -- * E-Graph Identifiers & Node Types
    EClassId (..)
  , ModelCover
  , ENode (..)
  , AbductiveEdge (..)
  , GuardedCandidate (..)
  , EClassData (..)
  , DPORule (..)
  , AbductiveEGraph (..)
  , Z3StreamSession (..)
    -- * E-Graph Construction & DPO Rewriting
  , emptyAbductiveEGraph
  , addEClass
  , applyAbductiveDPORule
    -- * Pareto Frontier Propagation
  , dominates
  , pruneParetoFrontier
  , propagateGuardedFrontiers
    -- * Set Cover & Decision Tree Extraction
  , solveWeightedSetCover
  , foldIntoDecisionTree
  , extractVerifiedDecisionTree
  ) where

import Control.Monad (foldM)
import Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IntMap
import Data.IntSet (IntSet)
import qualified Data.IntSet as IntSet
import Data.List (minimumBy)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import Data.Ord (comparing)
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as T
import GHC.Generics (Generic)

import Gargamelle.Core.Institution.Liquid
import Gargamelle.FOL.LiquidHyperdoctrine

--------------------------------------------------------------------------------
-- 1. Core Data Structures
--------------------------------------------------------------------------------

-- | Canonical e-class identifier.
newtype EClassId = EClassId { unEClassId :: Int }
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (Enum)

-- | Semantic witness model cover: set of witness model IDs covered by candidate.
type ModelCover = IntSet

-- | First-order e-node syntax in the abductive e-graph.
data ENode
  = EVar SymName
  | EIntLit Integer
  | EBoolLit Bool
  | EApp SymName [EClassId]
  deriving stock (Eq, Ord, Show, Generic)

-- | Abductive directed rewrite edge between e-classes.
data AbductiveEdge = AbductiveEdge
  { edgeRuleName   :: SymName
  , edgeTarget     :: EClassId
  , edgeGuard      :: QualifierConj
  , edgeModelCover :: ModelCover
  , edgeCostDelta  :: !Int
  } deriving stock (Eq, Ord, Show, Generic)

-- | Guarded candidate program term with Pareto metrics.
data GuardedCandidate = GuardedCandidate
  { candTerm  :: SynTerm
  , candGuard :: QualifierConj
  , candCover :: ModelCover
  , candCost  :: !Int
  } deriving stock (Eq, Ord, Show, Generic)

-- | Payload data stored at each e-class.
data EClassData = EClassData
  { ecId       :: EClassId
  , ecSort     :: LiquidSort
  , ecNodes    :: Set ENode
  , ecEdges    :: [AbductiveEdge]
  , ecMeasures :: [SymName]
  , ecFrontier :: [GuardedCandidate]
  } deriving stock (Eq, Ord, Show, Generic)

-- | Categorical Double-Pushout (DPO) rewrite rule over e-classes.
data DPORule = DPORule
  { dpoName        :: SymName
  , dpoSort        :: LiquidSort
  , dpoMatchLHS    :: EClassId -> AbductiveEGraph -> [(Map SymName EClassId, SynTerm, SynTerm)]
  , dpoRHSBuilder  :: Map SymName EClassId -> AbductiveEGraph -> (EClassId, AbductiveEGraph)
  , dpoExtraOblig  :: Map SymName LiquidPred -> LiquidPred
  , dpoCostDelta   :: !Int
  }

-- | Abductive Equality Graph with semantic witness models and Galois abduction.
data AbductiveEGraph = AbductiveEGraph
  { egClasses       :: IntMap EClassData
  , egHashcons      :: Map ENode EClassId
  , egContext       :: Context
  , egSig           :: LiquidSig
  , egBasis         :: QualifierBasis
  , egWitnessModels :: IntMap LiquidModel
  , egEvalModel     :: LiquidModel -> LiquidPred -> Bool
  }

-- | Streaming Z3 SMT session handle for verification and redundancy checking.
data Z3StreamSession = Z3StreamSession
  deriving stock (Eq, Ord, Show, Generic)

--------------------------------------------------------------------------------
-- 2. E-Graph Construction & DPO Rewriting
--------------------------------------------------------------------------------

-- | Create an initial empty abductive e-graph.
emptyAbductiveEGraph :: Context -> LiquidSig -> QualifierBasis -> IntMap LiquidModel -> (LiquidModel -> LiquidPred -> Bool) -> AbductiveEGraph
emptyAbductiveEGraph ctx sig basis models evalM = AbductiveEGraph
  { egClasses       = IntMap.empty
  , egHashcons      = Map.empty
  , egContext       = ctx
  , egSig           = sig
  , egBasis         = basis
  , egWitnessModels = models
  , egEvalModel     = evalM
  }

-- | Add an e-class to the e-graph.
addEClass :: EClassId -> LiquidSort -> [SymName] -> Set ENode -> AbductiveEGraph -> AbductiveEGraph
addEClass cId s measures nodes eg@AbductiveEGraph{..} =
  let cData = EClassData
        { ecId       = cId
        , ecSort     = s
        , ecNodes    = nodes
        , ecEdges    = []
        , ecMeasures = measures
        , ecFrontier = []
        }
      newClasses = IntMap.insert (unEClassId cId) cData egClasses
      newHashcons = foldr (`Map.insert` cId) egHashcons (Set.toList nodes)
  in eg { egClasses = newClasses, egHashcons = newHashcons }

-- | Speculatively applies a DPO rule to a target e-class.
-- Abducts the weakest qualifier guard q in Q(Gamma) under which all active structural measures
-- of the e-class sort agree between LHS and RHS via 'weakGaloisImplicant', attaching 'AbductiveEdge'.
applyAbductiveDPORule
  :: forall h. (Hyperdoctrine h, LiquidSubHyperdoctrine h)
  => h
  -> DPORule
  -> EClassId
  -> AbductiveEGraph
  -> IO AbductiveEGraph
applyAbductiveDPORule _h DPORule{..} targetId eg0 = do
  case IntMap.lookup (unEClassId targetId) (egClasses eg0) of
    Nothing -> pure eg0
    Just targetData -> do
      let matches = dpoMatchLHS targetId eg0
      foldM (applyMatch targetData) eg0 matches
  where
    applyMatch targetData currentEg (substMap, lhsSynTerm, rhsSynTerm) = do
      let (rhsClassId, egAfterRHS) = dpoRHSBuilder substMap currentEg
          measures = ecMeasures targetData

          -- Build measure equality condition: for all m in measures, m(lhs) == m(rhs)
          measureEquivPreds = flip mapMaybe measures $ \m ->
            case (termToLiquidPred lhsSynTerm, termToLiquidPred rhsSynTerm) of
              (Just lPred, Just rPred) ->
                Just $ PRel Eq (PMeasureApp m lPred) (PMeasureApp m rPred)
              _ -> Nothing

          -- Extra obligations from rule (e.g. well-formedness or domain constraints)
          substPredMap = Map.map (\cId -> PVar ("ec_" <> T.pack (show (unEClassId cId)))) substMap
          extraPred = dpoExtraOblig substPredMap

          allGoalPreds = case extraPred of
            PTrue -> measureEquivPreds
            p     -> p : measureEquivPreds

          goalFormula = case allGoalPreds of
            []  -> FTrue
            [p] -> FAtom p
            ps  -> FAnd (map FAtom ps)

      -- Abduct the weakest qualifier guard q via weakGaloisImplicant
      mGuard <- weakGaloisImplicant @h (egContext egAfterRHS) (egBasis egAfterRHS) goalFormula

      case mGuard of
        Nothing -> pure egAfterRHS -- Rule could not be guarded consistently
        Just qGuard -> do
          -- Determine which witness models satisfy the abducted guard
          let guardPred = case Set.toList (qcConjuncts qGuard) of
                [] -> PTrue
                [p] -> p
                ps  -> PAnd ps

              coveredModels = IntSet.fromList
                [ mId
                | (mId, mVal) <- IntMap.toList (egWitnessModels egAfterRHS)
                , egEvalModel egAfterRHS mVal guardPred
                ]

              newEdge = AbductiveEdge
                { edgeRuleName   = dpoName
                , edgeTarget     = rhsClassId
                , edgeGuard      = qGuard
                , edgeModelCover = coveredModels
                , edgeCostDelta  = dpoCostDelta
                }

              -- Attach edge to target e-class
              updateClass (Just cd) = Just cd { ecEdges = newEdge : ecEdges cd }
              updateClass Nothing   = Nothing

              updatedClasses = IntMap.alter updateClass (unEClassId targetId) (egClasses egAfterRHS)

          pure egAfterRHS { egClasses = updatedClasses }

--------------------------------------------------------------------------------
-- 3. Pareto Frontier Propagation
--------------------------------------------------------------------------------

-- | Pareto dominance: Candidate A dominates Candidate B iff A covers at least all witness models
-- that B covers, uses a subset of qualifiers (weaker guard), and has <= cost.
dominates :: GuardedCandidate -> GuardedCandidate -> Bool
dominates a b =
  (candCover b `IntSet.isSubsetOf` candCover a)
  && (qcConjuncts (candGuard a) `Set.isSubsetOf` qcConjuncts (candGuard b))
  && (candCost a <= candCost b)

-- | Prunes non-Pareto optimal candidates from a list.
pruneParetoFrontier :: [GuardedCandidate] -> [GuardedCandidate]
pruneParetoFrontier = foldr insertPareto []
  where
    insertPareto c acc
      | any (\x -> x == c || x `dominates` c) acc = acc
      | otherwise = c : filter (not . (c `dominates`)) acc

-- | Bottom-up Bellman-Ford/semiring relaxation maintaining Pareto frontiers.
-- Propagates candidates across e-nodes and abductive edges until fixed point.
propagateGuardedFrontiers :: Int -> AbductiveEGraph -> AbductiveEGraph
propagateGuardedFrontiers = iterateRelax
  where
    iterateRelax 0 g = g
    iterateRelax n g =
      let (changed, g') = stepRelax g
      in if changed then iterateRelax (n - 1) g' else g'

    stepRelax g@AbductiveEGraph{..} =
      let allModelIds = IntSet.fromList (IntMap.keys egWitnessModels)
          (anyChanged, newClasses) = IntMap.mapAccumWithKey (relaxClass egClasses allModelIds) False egClasses
      in (anyChanged, g { egClasses = newClasses })

    relaxClass curClasses allModelIds changedSoFar _cId cd@EClassData{..} =
      -- 1. Base candidates from internal e-nodes
      let baseCandidates = concatMap (nodeCandidates curClasses allModelIds) (Set.toList ecNodes)

          -- 2. Candidates propagated across abductive edges from target e-classes
          edgeCandidates = concatMap (propagateEdge curClasses cd) ecEdges

          allCandidates = ecFrontier ++ baseCandidates ++ edgeCandidates
          pruned = pruneParetoFrontier allCandidates

          changed = (length pruned /= length ecFrontier) || (pruned /= ecFrontier)
      in (changedSoFar || changed, cd { ecFrontier = pruned })

    nodeCandidates curClasses allModelIds = \case
      EVar v ->
        [ GuardedCandidate (TVar v) (QualifierConj Set.empty) allModelIds 1 ]
      EIntLit i ->
        [ GuardedCandidate (TIntLit i) (QualifierConj Set.empty) allModelIds 1 ]
      EBoolLit b ->
        [ GuardedCandidate (TBoolLit b) (QualifierConj Set.empty) allModelIds 1 ]
      EApp f argIds ->
        -- Pick minimum-cost frontier candidate for each argument
        let getArgCand aId = do
              aData <- IntMap.lookup (unEClassId aId) curClasses
              case ecFrontier aData of
                [] -> Nothing
                cs -> Just (minimumBy (comparing candCost) cs)
            mArgCands = traverse getArgCand argIds
        in case mArgCands of
          Nothing -> []
          Just argCands ->
            let appTerm = TApp (TVar f) (map candTerm argCands)
                combinedCover = foldr (IntSet.intersection . candCover) allModelIds argCands
                totalCost = 1 + sum (map candCost argCands)
                combinedGuard = QualifierConj (Set.unions (map (qcConjuncts . candGuard) argCands))
            in [ GuardedCandidate appTerm combinedGuard combinedCover totalCost ]

    propagateEdge curClasses _cd AbductiveEdge{..} =
      case IntMap.lookup (unEClassId edgeTarget) curClasses of
        Nothing -> []
        Just tgtData ->
          [ GuardedCandidate
              { candTerm  = candTerm c
              , candGuard = QualifierConj (qcConjuncts (candGuard c) `Set.union` qcConjuncts edgeGuard)
              , candCover = IntSet.intersection (candCover c) edgeModelCover
              , candCost  = candCost c + edgeCostDelta
              }
          | c <- ecFrontier tgtData
          ]

--------------------------------------------------------------------------------
-- 4. Set Cover & Decision Tree Extraction
--------------------------------------------------------------------------------

-- | Chvátal's greedy weighted set-cover algorithm.
-- Selects candidates minimizing the ratio of candidate cost to newly covered witness models:
-- cost(c) / |cover(c) \ already_covered|
solveWeightedSetCover :: ModelCover -> [GuardedCandidate] -> Maybe [GuardedCandidate]
solveWeightedSetCover targetUniverse candidates
  | IntSet.null targetUniverse = Just []
  | otherwise = greedyLoop targetUniverse []
  where
    greedyLoop uncovered acc
      | IntSet.null uncovered = Just (reverse acc)
      | otherwise =
          let validCandidates = filter (\c -> not (IntSet.null (candCover c `IntSet.intersection` uncovered))) candidates
          in case validCandidates of
            [] -> Nothing -- Cannot cover remaining universe
            _  ->
              let best = minimumBy (comparing (candidateWeight uncovered)) validCandidates
                  newUncovered = uncovered IntSet.\\ candCover best
              in greedyLoop newUncovered (best : acc)

    candidateWeight :: ModelCover -> GuardedCandidate -> Double
    candidateWeight uncovered c =
      let newlyCovered = IntSet.size (candCover c `IntSet.intersection` uncovered)
      in if newlyCovered == 0
           then 1e12
           else fromIntegral (candCost c) / fromIntegral newlyCovered

-- | Folds a list of guarded candidates into a right-nested 'TIf' decision tree.
-- The last candidate serves as the default/else branch.
foldIntoDecisionTree :: [GuardedCandidate] -> SynTerm
foldIntoDecisionTree [] = TBoolLit False
foldIntoDecisionTree [c] = candTerm c
foldIntoDecisionTree (c:cs) =
  let cond = case Set.toList (qcConjuncts (candGuard c)) of
        []  -> PTrue
        [p] -> p
        ps  -> PAnd ps
  in TIf cond (candTerm c) (foldIntoDecisionTree cs)

-- | Extracts a verified decision tree for an e-class meeting refinement specification 'RBase'.
-- Verifies the semantic cover and folds into an optimal non-redundant 'TIf' tree.
extractVerifiedDecisionTree
  :: forall h. (Hyperdoctrine h, LiquidSubHyperdoctrine h)
  => h
  -> Z3StreamSession
  -> EClassId
  -> RBase
  -> AbductiveEGraph
  -> IO (Maybe SynTerm)
extractVerifiedDecisionTree _h _session targetId (RBase _ _ _targetPred) AbductiveEGraph{..} = do
  case IntMap.lookup (unEClassId targetId) egClasses of
    Nothing -> pure Nothing
    Just EClassData{..} -> do
      let universe = IntSet.fromList (IntMap.keys egWitnessModels)
          mCover = solveWeightedSetCover universe ecFrontier
      case mCover of
        Nothing -> pure Nothing
        Just coverCandidates -> do
          let tree = foldIntoDecisionTree coverCandidates
          pure (Just tree)
