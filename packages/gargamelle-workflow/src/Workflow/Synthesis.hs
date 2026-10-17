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

-- | Milestone M3: Crem State Machine Synthesis Loop
--
-- Orchestrates the autonomous synthesis loop using Tweag's Crem library:
-- ProposeChange -> SandboxRun -> CollectEvidence -> SimilarityCheck -> StateTransition
-- with transitions formally verified at compile time.
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
  ) where

import Crem.BaseMachine
import Crem.Render.RenderableVertices (AllVertices (..), RenderableVertices)
import Crem.StateMachine
import Crem.Topology
import "singletons-base" Data.Singletons.Base.TH
import Data.Functor.Identity (Identity(..), runIdentity)
import Data.Text (Text)
import Data.TreeDiff (ToExpr(..), Expr(..), Edit(..), EditExpr(..), exprDiff)
import qualified Data.TreeDiff.OMap as OMap

$( singletons
     [d|
       data SynthesisVertex
         = StatePropose
         | StateSandboxRun
         | StateCollectEvidence
         | StateSimilarityCheck
         | StateComplete
         deriving stock (Eq, Show, Enum, Bounded)

       synthesisTopology :: Topology SynthesisVertex
       synthesisTopology =
         Topology
           [ (StatePropose, [StateSandboxRun, StateComplete])
           , (StateSandboxRun, [StateCollectEvidence, StateComplete])
           , (StateCollectEvidence, [StateSimilarityCheck, StateComplete])
           , (StateSimilarityCheck, [StatePropose, StateComplete])
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
  | CmdCheckSimilarity Bool
  | CmdReset
  deriving (Show, Eq)

-- | Events emitted by the synthesis state machine
data SynthesisEvent
  = EvtCandidateProposed Text
  | EvtSandboxCompleted (Int, Text)
  | EvtEvidenceRecorded Text
  | EvtSynthesisSucceeded Text
  | EvtSynthesisRetry Text
  | EvtResetDone
  deriving (Show, Eq)

-- | The core Mealy machine enforcing the synthesis loop topology
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
          _ ->
            pureResult (EvtSynthesisRetry "Unexpected command in CollectEvidence state") SStateCollectEvidence
        SStateSimilarityCheck -> \case
          CmdCheckSimilarity isSimilar ->
            if isSimilar
              then pureResult (EvtSynthesisRetry "Similar known failure detected, proposing alternative") SStatePropose
              else pureResult (EvtSynthesisSucceeded "New valid candidate synthesized") SStateComplete
          _ ->
            pureResult (EvtSynthesisRetry "Unexpected command in SimilarityCheck state") SStateSimilarityCheck
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

-- | Compute AST similarity between two TreeDiff Exprs in range [0.0, 1.0]
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

