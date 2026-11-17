{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : Gargamelle.Audit.Repair
Description : Structured JSON Repair Diagnostics Generator for Yamaarashi Self-Repair
Copyright   : (c) Nadia Yvette Chambers, 2026
License     : EUPL-1.2

@purpose
Transforms ratchet audit violations into structured JSON repair directives and templates.

@behavior
Synthesizes actionable fix hints and code stubs for MissingKnowledgeSlots,
WorkingMemoryPeakExceeded, ExcessiveParameterArity, and TautologicalDocstring.

@theory
Closed-loop agent self-repair and prompt synthesis from formal AST diagnostics.

@contracts
Purity: Deterministic transformation from RatchetVerdict to YamaarashiRepairPacket.

@pattern
Deterministic mapping over violation categories.

@example
buildRepairPacket verdict
-}

module Gargamelle.Audit.Repair
  ( RepairDirective (..)
  , YamaarashiRepairPacket (..)
  , buildRepairPacket
  ) where

import Data.Aeson (FromJSON, ToJSON)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BSL
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import GHC.Generics (Generic)

import Gargamelle.Audit.Types
  ( AuditViolation (..)
  , KnowledgeSlot (..)
  , RatchetVerdict (..)
  , ViolationCategory (..)
  )

data RepairDirective = RepairDirective
  { rdFilePath        :: !FilePath
  , rdSymbol          :: !Text
  , rdLineRange       :: !(Int, Int)
  , rdViolationType   :: !Text
  , rdConcreteFixHint :: !Text
  , rdTemplateSnippet :: !(Maybe Text)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

data YamaarashiRepairPacket = YamaarashiRepairPacket
  { yrpBlockingCount :: !Int
  , yrpDirectives    :: ![RepairDirective]
  , yrpPromptPayload :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

buildRepairPacket :: RatchetVerdict -> YamaarashiRepairPacket
buildRepairPacket verdict =
  let blocking = rvBlockingViolations verdict
      directives = map violationToDirective blocking
      jsonBytes = Aeson.encode directives
      jsonText = TE.decodeUtf8 (BSL.toStrict jsonBytes)
      payload = synthesizePrompt blocking directives jsonText
  in YamaarashiRepairPacket
       { yrpBlockingCount = length blocking
       , yrpDirectives    = directives
       , yrpPromptPayload = payload
       }

violationToDirective :: AuditViolation -> RepairDirective
violationToDirective v =
  let (vType, hint, snippet) = categorize (avCategory v) (avSymbol v)
  in RepairDirective
       { rdFilePath        = avFilePath v
       , rdSymbol          = avSymbol v
       , rdLineRange       = (avStartLine v, avEndLine v)
       , rdViolationType   = vType
       , rdConcreteFixHint = hint
       , rdTemplateSnippet = snippet
       }
  where
    categorize cat sym = case cat of
      MissingKnowledgeSlots ms ->
        ( "MissingKnowledgeSlots"
        , "Add missing Maalej-Robillard knowledge slots to docblock for " <> sym
        , Just (synthesizeSlotSnippet ms)
        )
      WorkingMemoryPeakExceeded peak limit spanCount ->
        ( "WorkingMemoryPeakExceeded"
        , "Peak live variables " <> T.pack (show peak) <> " exceeds limit " <> T.pack (show limit)
          <> " over span of " <> T.pack (show spanCount) <> " lines; extract helper function."
        , Nothing
        )
      ExcessiveParameterArity count limit ->
        ( "ExcessiveParameterArity"
        , "Parameter arity " <> T.pack (show count) <> " exceeds public API limit " <> T.pack (show limit)
          <> "; bundle arguments into a record."
        , Just ("data " <> sym <> "Params = " <> sym <> "Params { ... }")
        )
      TautologicalDocstring meas req ->
        ( "TautologicalDocstring"
        , "Novel stem ratio " <> T.pack (show meas) <> " is below minimum " <> T.pack (show req)
          <> "; describe operational invariants and algorithmic behavior."
        , Nothing
        )
      MissingFunctionContract ->
        ( "MissingFunctionContract"
        , "Function missing contract/complexity annotation; add @contracts / @complexity tag or O(...) bound."
        , Just "-- | ...\n-- @contracts Total, monotonic\n-- @complexity O(n)"
        )
      ApiReachabilityExceeded _ meas maxH ->
        ( "ApiReachabilityExceeded"
        , "API helper type distance " <> T.pack (show meas) <> " exceeds max hops " <> T.pack (show maxH)
        , Nothing
        )
      PedagogicalForwardRef c u d ->
        ( "PedagogicalForwardRef"
        , "Concept " <> c <> " used in " <> u <> " before defined" <> maybe "" (" in " <>) d
          <> "; define earlier or add <!-- @spiral: " <> c <> " -->"
        , Just ("<!-- @spiral: " <> c <> " -->")
        )
      ExcessiveDefUseGap s g ->
        ( "ExcessiveDefUseGap"
        , "Symbol " <> s <> " used " <> T.pack (show g) <> " paragraphs before definition block."
        , Nothing
        )

synthesizeSlotSnippet :: [KnowledgeSlot] -> Text
synthesizeSlotSnippet ms =
  let lines_ =
        [ "{-|"
        , "Module      : ..."
        ]
        ++ [ tagForSlot s | s <- ms ]
        ++ [ "-}" ]
  in T.unlines lines_
  where
    tagForSlot SlotPurpose         = "@purpose High level objective"
    tagForSlot SlotBehavior        = "@behavior Operational mechanics"
    tagForSlot SlotTheory          = "@theory Formal invariants and design principles"
    tagForSlot SlotContracts       = "@contracts Preconditions, postconditions, and complexity"
    tagForSlot SlotPattern         = "@pattern Architectural archetype"
    tagForSlot SlotExample         = "@example Code usage sample"
    tagForSlot SlotSafetyInvariant = "@safety_invariant Substrate memory safety preconditions"

synthesizePrompt :: [AuditViolation] -> [RepairDirective] -> Text -> Text
synthesizePrompt blocking _ jsonDirectives =
  T.unlines
    [ "# Yamaarashi Closed-Loop Audit Repair Prompt"
    , ""
    , "The verification harness detected " <> T.pack (show (length blocking)) <> " blocking audit violation(s)."
    , "Apply the structured directives below to resolve the violations:"
    , ""
    , "```json"
    , jsonDirectives
    , "```"
    ]
