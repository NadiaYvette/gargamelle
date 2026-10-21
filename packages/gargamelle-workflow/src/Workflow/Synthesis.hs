{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE StandaloneKindSignatures #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-unticked-promoted-constructors #-}
{-# OPTIONS_GHC -Wno-unused-type-patterns #-}
{-# OPTIONS_GHC -Wno-redundant-constraints #-}
{-# OPTIONS_GHC -Wno-unused-top-binds #-}

-- | Milestone M3 & Phase 6: Crem State Machine & Sheaf-Gated CEGIS Synthesis Loop
--
-- Orchestrates the autonomous synthesis loop using Tweag's Crem library:
-- ProposeChange -> SandboxRun -> CollectEvidence -> SimilarityCheck -> SheafCheck -> StateTransition
-- with transitions formally verified at compile time.
--
-- Phase 6 adds homological fault localization ($H^1$ cohomological obstructions)
-- from 'Gargamelle.Sheaf', wiring physical Bubblewrap sandboxing ('Sandbox.Handler')
-- and Beam SQLite persistence ('Persistence.Beam') into a unified CEGIS pipeline.
module Workflow.Synthesis
  ( -- * State Machine Types & Topology
    SynthesisVertex(..)
  , SSynthesisVertex(..)
  , SynthesisTopology
  , synthesisTopology
    -- * Commands and Events
  , SynthesisCommand(..)
  , SynthesisEvent(..)
    -- * Machine Constructor & Runner
  , synthesisMachine
  , createSynthesisMachine
  , stepSynthesis
  , runSynthesisBatch
    -- * AST Structural Similarity via tree-diff
  , computeExprSimilarity
  , computeTreeDiffSimilarity
  , isAstStructurallySimilar
    -- * End-to-End Sheaf-Gated CEGIS Pipeline
  , SheafCEGISConfig(..)
  , SheafCEGISOutcome(..)
  , runSheafGatedCEGIS
  , runSheafGatedCEGISWithRunner
  , runSheafGatedCEGISWithDiffusion
  , runSheafGatedCEGISWithDiffusionAndRunner
  ) where

import Algebra.Lattice (BoundedMeetSemiLattice)
import Crem.BaseMachine
import Crem.Render.RenderableVertices (AllVertices (..), RenderableVertices)
import Crem.StateMachine
import Crem.Topology
import "singletons-base" Data.Singletons.Base.TH
import Data.Functor.Identity (Identity(..), runIdentity)
import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as T
import Data.TreeDiff (ToExpr(..), Expr(..), Edit(..), EditExpr(..), exprDiff)
import qualified Data.TreeDiff.OMap as OMap
import Database.SQLite.Simple (Connection)
import Gargamelle.Sheaf.Complex (CellComplex)
import Gargamelle.Sheaf.Diffusion (CellularSheaf, Cochain0, diffuseUntilHarmonic)
import Gargamelle.Sheaf.Cohomology (GlobalSection(..), InterfaceObstruction(..), locateObstructions)
import Persistence.Beam
  ( initEvidenceDb
  , insertEvidenceRecord
  , findEvidenceByRep
  , insertCounterexample
  , startRunRecord
  , completeRunRecord
  )
import Persistence.Schema (EvidenceRecordT(..))
import Sandbox.Effect (ResourceLimits(..))
import Sandbox.Handler (executeSandboxed)

$( singletons
     [d|
       data SynthesisVertex
         = StatePropose
         | StateSandboxRun
         | StateCollectEvidence
         | StateSimilarityCheck
         | StateSheafCheck
         | StateComplete
         deriving stock (Eq, Show, Enum, Bounded)

       synthesisTopology :: Topology SynthesisVertex
       synthesisTopology =
         Topology
           [ (StatePropose, [StateSandboxRun, StateSheafCheck, StateComplete])
           , (StateSandboxRun, [StateCollectEvidence, StateComplete])
           , (StateCollectEvidence, [StateSimilarityCheck, StateSheafCheck, StateComplete])
           , (StateSimilarityCheck, [StatePropose, StateSheafCheck, StateComplete])
           , (StateSheafCheck, [StatePropose, StateComplete])
           , (StateComplete, [StatePropose])
           ]
       |]
 )

deriving via AllVertices SynthesisVertex instance RenderableVertices SynthesisVertex

-- | Commands sent to drive the synthesis state machine
data SynthesisCommand
  = CmdProposeCandidate Text
  | CmdRunSandbox (Int, Text, Text)
  | CmdEvaluateEvidence (Maybe Text)
  | CmdEvaluateEvidenceWithSheaf (Maybe Text)
  | CmdCheckSimilarity Bool
  | CmdCheckSimilarityWithSheaf Bool
  | CmdTransitionToSheafCheck
  | CmdEvaluateSheaf Bool [Text]
  | CmdReset
  deriving (Show, Eq)

-- | Events emitted by the synthesis state machine
data SynthesisEvent
  = EvtCandidateProposed Text
  | EvtSandboxCompleted (Int, Text)
  | EvtEvidenceRecorded Text
  | EvtSimilarityChecked Bool
  | EvtSheafHarmonicVerified Text
  | EvtSheafObstructionsDetected [Text]
  | EvtSynthesisSucceeded Text
  | EvtSynthesisRetry Text
  | EvtResetDone
  deriving (Show, Eq)

{- Note [Formally Verified Mealy Automata State Topology]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-crem-mealy-topology]
In autonomous program synthesis, state transitions between stages of generation,
sandboxed evaluation, failure analysis, and repair must be strictly controlled.
Allowing a synthesis loop to arbitrarily skip sandboxed compilation or bypass
evidence collection leads to invalid certification.

Gargamelle enforces its synthesis state graph at compile time via Tweag's 'crem'
library and 'singletons-base':
  1. Vertex Type: 'SynthesisVertex' defines the 6 discrete states:
       - StatePropose: Initial candidate generation and patch proposal.
       - StateSandboxRun: Execution inside isolated Bubblewrap container.
       - StateCollectEvidence: Evidence extraction and SMT counterexample gathering.
       - StateSimilarityCheck: Structural diff comparison with known failures.
       - StateSheafCheck: Topological evaluation of sheaf coboundaries.
       - StateComplete: Termination upon verified proof or failure limit.

  2. Type-Level Topology: 'synthesisTopology' lists the strictly permitted directed
     edges between vertices. Any transition not explicitly listed in the topology
     fails to compile with a type error during 'BaseMachineT' construction.

  3. Mealy Machine Semantics: 'synthesisMachine' maps (State, Command) pairs to
     (Event, NextState). Illegal commands in any state transition soundly to
     'EvtSynthesisRetry' or 'EvtResetDone' without undefined behavior or state corruption.
-}

-- | The core Mealy machine enforcing the synthesis loop topology.
--
-- See Note [Formally Verified Mealy Automata State Topology] [ref:note-crem-mealy-topology].
synthesisMachine
  :: SSynthesisVertex a
  -> BaseMachine SynthesisTopology SynthesisCommand SynthesisEvent
synthesisMachine initial =
  BaseMachineT
    { initialState = InitialState initial
    , action = \case
        SStatePropose -> \case
          CmdProposeCandidate cand ->
            pureResult (EvtCandidateProposed cand) SStateSandboxRun
          CmdTransitionToSheafCheck ->
            pureResult (EvtCandidateProposed "Direct sheaf verification") SStateSheafCheck
          CmdReset ->
            pureResult EvtResetDone SStatePropose
          _ ->
            pureResult (EvtSynthesisRetry "Unexpected command in Propose state") SStatePropose
        SStateSandboxRun -> \case
          CmdRunSandbox (code, out, err) ->
            if code == 0
              then pureResult (EvtSandboxCompleted (code, out)) SStateCollectEvidence
              else pureResult (EvtSynthesisRetry ("Sandbox failed: " <> err)) SStateComplete
          _ ->
            pureResult (EvtSynthesisRetry "Unexpected command in SandboxRun state") SStateSandboxRun
        SStateCollectEvidence -> \case
          CmdEvaluateEvidence mEv ->
            case mEv of
              Just ev -> pureResult (EvtEvidenceRecorded ev) SStateSimilarityCheck
              Nothing -> pureResult (EvtSynthesisSucceeded "Clean pass without failure evidence") SStateComplete
          CmdEvaluateEvidenceWithSheaf mEv ->
            case mEv of
              Just ev -> pureResult (EvtEvidenceRecorded ev) SStateSimilarityCheck
              Nothing -> pureResult (EvtEvidenceRecorded "Clean sandbox, proceeding to sheaf check") SStateSheafCheck
          _ ->
            pureResult (EvtSynthesisRetry "Unexpected command in CollectEvidence state") SStateCollectEvidence
        SStateSimilarityCheck -> \case
          CmdCheckSimilarity isSimilar ->
            if isSimilar
              then pureResult (EvtSynthesisRetry "Similar known failure detected, proposing alternative") SStatePropose
              else pureResult (EvtSynthesisSucceeded "New valid candidate synthesized") SStateComplete
          CmdCheckSimilarityWithSheaf isSimilar ->
            if isSimilar
              then pureResult (EvtSynthesisRetry "Similar known failure detected, proposing alternative") SStatePropose
              else pureResult (EvtSimilarityChecked False) SStateSheafCheck
          CmdTransitionToSheafCheck ->
            pureResult (EvtSimilarityChecked False) SStateSheafCheck
          CmdEvaluateSheaf isHarmonic obstructions ->
            if isHarmonic
              then pureResult (EvtSheafHarmonicVerified "Harmonic global section verified; H^1 = 0") SStateComplete
              else pureResult (EvtSheafObstructionsDetected obstructions) SStatePropose
          _ ->
            pureResult (EvtSynthesisRetry "Unexpected command in SimilarityCheck state") SStateSimilarityCheck
        SStateSheafCheck -> \case
          CmdEvaluateSheaf isHarmonic obstructions ->
            if isHarmonic
              then pureResult (EvtSheafHarmonicVerified "Harmonic global section verified; H^1 = 0") SStateComplete
              else pureResult (EvtSheafObstructionsDetected obstructions) SStatePropose
          _ ->
            pureResult (EvtSynthesisRetry "Unexpected command in SheafCheck state") SStateSheafCheck
        SStateComplete -> \case
          CmdReset ->
            pureResult EvtResetDone SStatePropose
          _ ->
            pureResult (EvtSynthesisSucceeded "Already complete") SStateComplete
    }

-- | Create a composable Crem StateMachine initialized to StatePropose
createSynthesisMachine :: StateMachineT Identity SynthesisCommand SynthesisEvent
createSynthesisMachine = Basic (synthesisMachine SStatePropose)

-- | Step the state machine forward with a single command
stepSynthesis
  :: StateMachineT Identity SynthesisCommand SynthesisEvent
  -> SynthesisCommand
  -> (SynthesisEvent, StateMachineT Identity SynthesisCommand SynthesisEvent)
stepSynthesis machine cmd = runIdentity (run machine cmd)

-- | Run a sequence of synthesis commands, returning all events and the final machine
runSynthesisBatch
  :: StateMachineT Identity SynthesisCommand SynthesisEvent
  -> [SynthesisCommand]
  -> ([SynthesisEvent], StateMachineT Identity SynthesisCommand SynthesisEvent)
runSynthesisBatch m [] = ([], m)
runSynthesisBatch m (c:cs) =
  let (e, m') = stepSynthesis m c
      (es, m'') = runSynthesisBatch m' cs
  in (e : es, m'')

{- Note [AST Tree-Diff Structural Similarity Heuristics]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-ast-structural-similarity]
In Counterexample-Guided Inductive Synthesis (CEGIS), generative models or symbolic
enumerators frequently propose superficial variants of previously refuted candidates
(such as renaming variables, reordering commutative operations, or swapping redundant blocks).
Submitting these trivial variations to expensive SMT solvers or isolated container test
suites wastes compute and causes synthesis stagnation.

Gargamelle prevents redundant exploration using structural tree diffing ('tree-diff'):
  1. Generic Tree Representation: Any AST implementing 'ToExpr' (from 'tree-diff')
     is normalized into an algebraic 'Expr' tree.
  2. Edit Distance Calculation: 'exprDiff ea eb' calculates the minimal edit script
     between the two expression trees, classifying nodes into:
       - Cpy: Identical preserved subterms.
       - Swp / Ins / Del: Replaced, inserted, or deleted subterms.
  3. Normalized Structural Metric: 'computeExprSimilarity' computes the copy ratio:
       similarity = copies / (copies + changes) ∈ [0.0, 1.0]
  4. Pruning Threshold: If 'isAstStructurallySimilar threshold a b' exceeds the threshold
     (e.g. 0.8), the proposal is recognized as structurally equivalent to a known failure,
     immediately triggering 'CmdCheckSimilarity True' to guide the generator away from
     futile search regions.
-}

-- | Compute AST similarity between two TreeDiff Exprs in range [0.0, 1.0].
--
-- See Note [AST Tree-Diff Structural Similarity Heuristics] [ref:note-ast-structural-similarity].
computeExprSimilarity :: Expr -> Expr -> Double
computeExprSimilarity ea eb =
  let editTree = exprDiff ea eb
      (copies, changes) = countEdits editTree
      total = copies + changes
  in if total == 0
       then 1.0
       else fromIntegral copies / fromIntegral total

-- | Compute structural similarity between any two types instantiating ToExpr
computeTreeDiffSimilarity :: (ToExpr a) => a -> a -> Double
computeTreeDiffSimilarity a b =
  let ea = toExpr a
      eb = toExpr b
  in computeExprSimilarity ea eb

-- | Decide if two AST values are structurally similar within a given threshold
isAstStructurallySimilar :: (ToExpr a) => Double -> a -> a -> Bool
isAstStructurallySimilar threshold a b =
  computeTreeDiffSimilarity a b >= threshold

countEdits :: Edit EditExpr -> (Int, Int)
countEdits (Cpy ee) =
  let (c, ch) = countEE ee
  in (1 + c, ch)
countEdits (Swp ee1 ee2) =
  let (_, ch1) = countEE ee1
      (_, ch2) = countEE ee2
  in (0, 2 + ch1 + ch2)
countEdits (Ins ee) =
  let (_, ch) = countEE ee
  in (0, 1 + ch)
countEdits (Del ee) =
  let (_, ch) = countEE ee
  in (0, 1 + ch)

countEE :: EditExpr -> (Int, Int)
countEE (EditApp _ es) = foldr (\e (accC, accCh) -> let (c, ch) = countEdits e in (accC + c, accCh + ch)) (0, 0) es
countEE (EditRec _ omap) = foldr (\e (accC, accCh) -> let (c, ch) = countEdits e in (accC + c, accCh + ch)) (0, 0) (OMap.elems omap)
countEE (EditLst es) = foldr (\e (accC, accCh) -> let (c, ch) = countEdits e in (accC + c, accCh + ch)) (0, 0) es
countEE (EditExp _) = (1, 0)

-- | Configuration for an end-to-end Sheaf-Gated CEGIS run
data SheafCEGISConfig vId eId stalk edgeStalk = SheafCEGISConfig
  { cegisDbConn        :: Connection
  , cegisRunId         :: Int64
  , cegisCandidateName :: Text
  , cegisChangeRep     :: Text
  , cegisSig           :: Text
  , cegisLimits        :: ResourceLimits
  , cegisSandboxCmd    :: (FilePath, [String])
  , cegisComplex       :: CellComplex vId eId
  , cegisSheaf         :: CellularSheaf vId eId stalk edgeStalk
  , cegisCandidateSpec :: Cochain0 vId stalk
  , cegisTimestamp     :: Int64
  }

-- | Outcome of an end-to-end Sheaf-Gated CEGIS synthesis run
data SheafCEGISOutcome vId eId stalk edgeStalk
  = SheafCEGISSuccess (GlobalSection vId stalk) Text
  | SheafCEGISObstruction [InterfaceObstruction eId edgeStalk]
  | SheafCEGISSandboxFailure Int Text
  | SheafCEGISPriorFailureFound Text
  deriving (Eq, Show)

{- Note [End-to-End Sheaf-Gated CEGIS Synthesis Loop]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-sheaf-gated-cegis-loop]
The 'runSheafGatedCEGIS' pipeline unifies all core subsystems of Gargamelle into
a closed-loop, verifiable autonomous synthesis engine:

Pipeline Execution Stages:
  1. Initial Propose: 'startRunRecord' logs the run in SQLite ('Persistence.Beam');
     'CmdProposeCandidate' enters the synthesis loop.
  2. Cache Check: 'findEvidenceByRep' queries past evidence records to reject
     candidates whose structural representations have already been disproved.
  3. Sandboxed Execution: 'executeSandboxed' runs candidate tests inside unprivileged
     Bubblewrap Linux containers ('Sandbox.Handler'), enforcing timeout and memory bounds.
  4. Evidence Recording: Sandboxed results are evaluated; if failure occurs,
     'insertEvidenceRecord' persists the witness to prevent future regression.
  5. Sheaf Cohomology Gate: 'coboundary' computes boundary discrepancies across the
     cell complex G = (V, E):
       - If H^1 = 0: All boundary restrictions match; 'GlobalSection' certifies the
         system, emitting 'SheafCEGISSuccess' and updating the run status to 'SUCCESS'.
       - If H^1 /= 0: 'locateObstructions' pinpoints exact failing interface edges,
         emitting 'SheafCEGISObstruction' and recording counterexamples into SQLite
         to directly guide targeted repair.
  6. Consensus Diffusion: With 'runSheafGatedCEGISWithDiffusion', Knaster-Tarski
     diffusion ('diffuseUntilHarmonic') reconciles flexible interface contracts
     before testing for hard cohomological obstructions.
-}

-- | Run end-to-end Sheaf-Gated CEGIS with production Bubblewrap sandbox runner.
--
-- See Note [End-to-End Sheaf-Gated CEGIS Synthesis Loop] [ref:note-sheaf-gated-cegis-loop].
runSheafGatedCEGIS
  :: (Ord vId, Ord eId, Show vId, Show eId, Show edgeStalk, Eq edgeStalk)
  => SheafCEGISConfig vId eId stalk edgeStalk
  -> IO (SheafCEGISOutcome vId eId stalk edgeStalk, [SynthesisEvent])
runSheafGatedCEGIS = runSheafGatedCEGISWithRunner executeSandboxed

-- | Run end-to-end Sheaf-Gated CEGIS with an injected sandbox execution runner.
runSheafGatedCEGISWithRunner
  :: forall vId eId stalk edgeStalk.
     (Ord vId, Ord eId, Show vId, Show eId, Show edgeStalk, Eq edgeStalk)
  => (ResourceLimits -> FilePath -> [String] -> IO (Int, Text, Text))
  -> SheafCEGISConfig vId eId stalk edgeStalk
  -> IO (SheafCEGISOutcome vId eId stalk edgeStalk, [SynthesisEvent])
runSheafGatedCEGISWithRunner sandboxRunner config = do
  let conn = cegisDbConn config
      rid = cegisRunId config
      cand = cegisCandidateName config
      rep = cegisChangeRep config
      sig = cegisSig config
      limits = cegisLimits config
      (cmd, args) = cegisSandboxCmd config
      complex = cegisComplex config
      sheaf = cegisSheaf config
      spec = cegisCandidateSpec config
      ts = cegisTimestamp config

  -- 1. Initialize SQLite schema & record start of run
  initEvidenceDb conn
  startRunRecord conn rid "RUNNING" ts

  -- 2. StatePropose: propose candidate
  let m0 = createSynthesisMachine
  let (e1, m1) = stepSynthesis m0 (CmdProposeCandidate cand)

  -- 3. Check for historical matching failure representation in Beam SQLite
  mPrior <- findEvidenceByRep conn rep
  case mPrior of
    Just priorRec -> do
      let (e2, m2) = stepSynthesis m1 (CmdRunSandbox (0, "cached-prior-check", ""))
      let (e3, m3) = stepSynthesis m2 (CmdEvaluateEvidence (Just (evidenceReason priorRec)))
      let (e4, _)  = stepSynthesis m3 (CmdCheckSimilarity True)
      completeRunRecord conn rid "RETRY_PRIOR_FAILURE" ts
      pure (SheafCEGISPriorFailureFound (evidenceReason priorRec), [e1, e2, e3, e4])

    Nothing -> do
      -- 4. StateSandboxRun: execute command under Bubblewrap / resource limits
      (code, out, err) <- sandboxRunner limits cmd args
      let (e2, m2) = stepSynthesis m1 (CmdRunSandbox (code, out, err))
      if code /= 0
        then do
          let evId = rid * 10
          insertEvidenceRecord conn evId sig rep ("Sandbox failure: " <> err) ts
          insertCounterexample conn (evId + 1) evId err
          completeRunRecord conn rid "FAILED_SANDBOX" ts
          pure (SheafCEGISSandboxFailure code err, [e1, e2])
        else do
          -- 5. StateCollectEvidence -> StateSimilarityCheck -> StateSheafCheck
          let (e3, m3) = stepSynthesis m2 (CmdEvaluateEvidence (Just "Sandbox clean pass; evaluating interface sheaves"))
          let (e4, m4) = stepSynthesis m3 (CmdCheckSimilarityWithSheaf False)

          -- 6. StateSheafCheck: compute H^1 coboundary and locate obstructions
          let obstructions = locateObstructions complex sheaf spec
          if null obstructions
            then do
              let (e5, _) = stepSynthesis m4 (CmdEvaluateSheaf True [])
              let evId = rid * 10
              insertEvidenceRecord conn evId sig rep "Harmonic global section verified; H^1 = 0" ts
              completeRunRecord conn rid "SUCCESS" ts
              pure (SheafCEGISSuccess (GlobalSection spec) "Harmonic global section verified; H^1 = 0", [e1, e2, e3, e4, e5])
            else do
              let obsTexts =
                    [ "Obstruction on edge " <> T.pack (show e) <> ": src=" <> T.pack (show s) <> " /= tgt=" <> T.pack (show t)
                    | InterfaceObstruction e s t <- obstructions
                    ]
              let (e5, _) = stepSynthesis m4 (CmdEvaluateSheaf False obsTexts)
              let evId = rid * 10
              insertEvidenceRecord conn evId sig rep ("Sheaf H^1 obstructions: " <> T.intercalate "; " obsTexts) ts
              mapM_ (\(i, obs) -> insertCounterexample conn (evId + i) evId (T.pack (show obs))) (zip [1..] obstructions)
              completeRunRecord conn rid "OBSTRUCTED_H1" ts
              pure (SheafCEGISObstruction obstructions, [e1, e2, e3, e4, e5])

-- | Run Sheaf-Gated CEGIS with Knaster-Tarski lattice diffusion.
runSheafGatedCEGISWithDiffusion
  :: (Ord vId, Ord eId, Show vId, Show eId, Show edgeStalk, Eq edgeStalk, BoundedMeetSemiLattice stalk, Eq stalk)
  => Int
  -> SheafCEGISConfig vId eId stalk edgeStalk
  -> IO (SheafCEGISOutcome vId eId stalk edgeStalk, [SynthesisEvent])
runSheafGatedCEGISWithDiffusion = runSheafGatedCEGISWithDiffusionAndRunner executeSandboxed

-- | Run Sheaf-Gated CEGIS with Knaster-Tarski lattice diffusion and an injected sandbox runner.
runSheafGatedCEGISWithDiffusionAndRunner
  :: forall vId eId stalk edgeStalk.
     (Ord vId, Ord eId, Show vId, Show eId, Show edgeStalk, Eq edgeStalk, BoundedMeetSemiLattice stalk, Eq stalk)
  => (ResourceLimits -> FilePath -> [String] -> IO (Int, Text, Text))
  -> Int
  -> SheafCEGISConfig vId eId stalk edgeStalk
  -> IO (SheafCEGISOutcome vId eId stalk edgeStalk, [SynthesisEvent])
runSheafGatedCEGISWithDiffusionAndRunner sandboxRunner maxDiffusionSteps config = do
  let conn = cegisDbConn config
      rid = cegisRunId config
      cand = cegisCandidateName config
      rep = cegisChangeRep config
      sig = cegisSig config
      limits = cegisLimits config
      (cmd, args) = cegisSandboxCmd config
      complex = cegisComplex config
      sheaf = cegisSheaf config
      spec = cegisCandidateSpec config
      ts = cegisTimestamp config

  initEvidenceDb conn
  startRunRecord conn rid "RUNNING" ts

  let m0 = createSynthesisMachine
  let (e1, m1) = stepSynthesis m0 (CmdProposeCandidate cand)

  mPrior <- findEvidenceByRep conn rep
  case mPrior of
    Just priorRec -> do
      let (e2, m2) = stepSynthesis m1 (CmdRunSandbox (0, "cached-prior-check", ""))
      let (e3, m3) = stepSynthesis m2 (CmdEvaluateEvidence (Just (evidenceReason priorRec)))
      let (e4, _)  = stepSynthesis m3 (CmdCheckSimilarity True)
      completeRunRecord conn rid "RETRY_PRIOR_FAILURE" ts
      pure (SheafCEGISPriorFailureFound (evidenceReason priorRec), [e1, e2, e3, e4])

    Nothing -> do
      (code, out, err) <- sandboxRunner limits cmd args
      let (e2, m2) = stepSynthesis m1 (CmdRunSandbox (code, out, err))
      if code /= 0
        then do
          let evId = rid * 10
          insertEvidenceRecord conn evId sig rep ("Sandbox failure: " <> err) ts
          insertCounterexample conn (evId + 1) evId err
          completeRunRecord conn rid "FAILED_SANDBOX" ts
          pure (SheafCEGISSandboxFailure code err, [e1, e2])
        else do
          let (e3, m3) = stepSynthesis m2 (CmdEvaluateEvidence (Just "Sandbox clean pass; evaluating interface sheaves"))
          let (e4, m4) = stepSynthesis m3 (CmdCheckSimilarityWithSheaf False)

          -- First check if initial spec is already harmonic
          let initialObstructions = locateObstructions complex sheaf spec
          if null initialObstructions
            then do
              let (e5, _) = stepSynthesis m4 (CmdEvaluateSheaf True [])
              let evId = rid * 10
              insertEvidenceRecord conn evId sig rep "Harmonic global section verified; H^1 = 0" ts
              completeRunRecord conn rid "SUCCESS" ts
              pure (SheafCEGISSuccess (GlobalSection spec) "Harmonic global section verified; H^1 = 0", [e1, e2, e3, e4, e5])
            else do
              -- Perform Knaster-Tarski Store diffusion over meet lattice
              let diffusedSpec = diffuseUntilHarmonic maxDiffusionSteps complex sheaf spec
              let postDiffusionObstructions = locateObstructions complex sheaf diffusedSpec
              if null postDiffusionObstructions
                then do
                  let (e5, _) = stepSynthesis m4 (CmdEvaluateSheaf True [])
                  let evId = rid * 10
                  insertEvidenceRecord conn evId sig rep "Harmonic global section attained via cellular diffusion; H^1 = 0" ts
                  completeRunRecord conn rid "SUCCESS_DIFFUSED" ts
                  pure (SheafCEGISSuccess (GlobalSection diffusedSpec) "Harmonic global section attained via cellular diffusion; H^1 = 0", [e1, e2, e3, e4, e5])
                else do
                  let obsTexts =
                        [ "Stubborn obstruction on edge " <> T.pack (show e) <> ": src=" <> T.pack (show s) <> " /= tgt=" <> T.pack (show t)
                        | InterfaceObstruction e s t <- postDiffusionObstructions
                        ]
                  let (e5, _) = stepSynthesis m4 (CmdEvaluateSheaf False obsTexts)
                  let evId = rid * 10
                  insertEvidenceRecord conn evId sig rep ("Sheaf H^1 stubborn obstructions: " <> T.intercalate "; " obsTexts) ts
                  mapM_ (\(i, obs) -> insertCounterexample conn (evId + i) evId (T.pack (show obs))) (zip [1..] postDiffusionObstructions)
                  completeRunRecord conn rid "OBSTRUCTED_H1" ts
                  pure (SheafCEGISObstruction postDiffusionObstructions, [e1, e2, e3, e4, e5])
