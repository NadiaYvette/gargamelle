{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : Gargamelle.Audit.Types
Description : Core Audit Schema, Violations, & Configuration Types
Copyright   : (c) Nadia Yvette Chambers, 2026
License     : EUPL-1.2

@purpose
Defines the core data structures for architectural audits, cognitive threshold
configuration, AST violation categories, ratchet baselines, and language adapters.

@behavior
Provides serialization and deserialization instances for threshold configuration,
violation reports, and baseline comparison records.

@theory
Cognitive load limits (Miller's Law, Sweller's cognitive load theory),
Maalej-Robillard documentation taxonomy, and zero-regression architectural ratchets.

@contracts
Purity: Pure value types with total Ord, Eq, Show, Generic, and Aeson instances.

@pattern
Typed domain model and immutable configuration record.

@example
let cfg = defaultAuditThresholds in maxLiveBindings cfg == 7
-}

module Gargamelle.Audit.Types
  ( AuditThresholds (..)
  , defaultAuditThresholds
  , SubstrateMode (..)
  , ViolationCategory (..)
  , KnowledgeSlot (..)
  , AuditViolation (..)
  , BaselineFingerprints (..)
  , RatchetVerdict (..)
  , CstLangAdapter (..)
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Set (Set)
import Data.Text (Text)
import GHC.Generics (Generic)

data AuditThresholds = AuditThresholds
  { maxLiveBindings     :: !Int     -- Default: 7
  , minLiveSpanLines    :: !Int     -- Default: 15
  , maxExplicitParams   :: !Int     -- Default: 4
  , minNovelStemRatio   :: !Double  -- Default: 1.5
  , maxApiHops          :: !Int     -- Default: 2
  , maxDefUseParagraphs :: !Int     -- Default: 3
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

defaultAuditThresholds :: AuditThresholds
defaultAuditThresholds = AuditThresholds
  { maxLiveBindings     = 7
  , minLiveSpanLines    = 15
  , maxExplicitParams   = 4
  , minNovelStemRatio   = 1.5
  , maxApiHops          = 2
  , maxDefUseParagraphs = 3
  }

data SubstrateMode
  = StandardModule
  | SubstrateModule -- Triggered by `.Internal` module suffix or `{-# ANN module "audit:substrate" #-}`
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data KnowledgeSlot
  = SlotPurpose
  | SlotBehavior
  | SlotTheory
  | SlotContracts
  | SlotPattern
  | SlotExample
  | SlotSafetyInvariant -- Mandatory when SubstrateMode == SubstrateModule
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)
  deriving anyclass (FromJSON, ToJSON)

data ViolationCategory
  = WorkingMemoryPeakExceeded { peakCount :: !Int, limitCount :: !Int, spanLines :: !Int }
  | ExcessiveParameterArity   { paramCount :: !Int, limitParams :: !Int }
  | TautologicalDocstring     { measuredRatio :: !Double, requiredRatio :: !Double }
  | MissingKnowledgeSlots     { missingSlots :: ![KnowledgeSlot] }
  | MissingFunctionContract
  | ApiReachabilityExceeded   { helperType :: !Text, measuredHops :: !(Maybe Int), maxHops :: !Int }
  | PedagogicalForwardRef     { conceptOrSymbol :: !Text, usedInDoc :: !Text, definedInDoc :: !(Maybe Text) }
  | ExcessiveDefUseGap        { symbolName :: !Text, paragraphGap :: !Int }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data AuditViolation = AuditViolation
  { avFilePath    :: !FilePath
  , avSymbol      :: !Text
  , avStartLine   :: !Int
  , avEndLine     :: !Int
  , avCategory    :: !ViolationCategory
  , avRemediation :: !Text
  } deriving stock (Eq, Ord, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

newtype BaselineFingerprints = BaselineFingerprints
  { unFingerprints :: Set (FilePath, Text, ViolationCategory)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

data RatchetVerdict = RatchetVerdict
  { rvBlockingViolations    :: ![AuditViolation]
  , rvGrandfatheredCount    :: !Int
  , rvResolvedBaselineCount :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

data CstLangAdapter = CstLangAdapter
  { claLanguageName :: !Text
  , claExtensions   :: ![String]
  , claAnalyzeFile  :: AuditThresholds -> FilePath -> Text -> [AuditViolation]
  }
