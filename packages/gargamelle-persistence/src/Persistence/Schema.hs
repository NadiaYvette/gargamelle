{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

-- | Milestone M2: Beam Persistence Schema
--
-- Defines database tables for storing structured evidence, SMT counterexamples,
-- and autonomous execution runs using the Beam ORM.
module Persistence.Schema
  ( -- * Evidence Table
    EvidenceRecordT(..)
  , EvidenceRecord
  , EvidenceRecordId
  , PrimaryKey(..)
    -- * Counterexample Table
  , CounterexampleRecordT(..)
  , CounterexampleRecord
  , CounterexampleRecordId
    -- * Pipeline Run Table
  , RunRecordT(..)
  , RunRecord
  , RunRecordId
    -- * Database Schema
  , EvidenceDb(..)
  , evidenceDb
  ) where

import Data.Int (Int64)
import Data.Text (Text)
import Database.Beam
import Database.Beam.Schema.Tables ()

{- Note [Beam SQLite Relational Persistence and Concurrency Locking]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-beam-sqlite-persistence]
In autonomous multi-agent synthesis loops and counterexample-guided inductive synthesis
(CEGIS), maintaining a durable, relational record of past verification trials is essential:
  1. Preventing Regression Loops: Without persistent storage, an iterative synthesizer
     has no memory across restarts or parallel runs, leading to the repeated generation of
     previously refuted hypotheses.
  2. Structured Relational Foreign Keys: Counterexamples are not arbitrary log strings;
     they are concrete mathematical witnesses linked via foreign keys ('counterexampleEvidenceRef')
     to the specific structural change ('evidenceChangeRep') and signature ('evidenceSig')
     that triggered the failure.
  3. Compile-Time Type-Safe Beam Schemas:
     By leveraging Beam's higher-kinded data (HKD) table encoding:
       data EvidenceRecordT f = EvidenceRecord { evidenceId :: Columnar f Int64, ... }
     queries and joins are validated at compile time by GHC. Column names, primary keys,
     and foreign key references cannot drift out of sync with Haskell types.
  4. Concurrency & File-Locking Invariants:
     SQLite provides zero-configuration, serverless transactional persistence. In multi-agent
     and parallel synthesis workflows, WAL (Write-Ahead Logging) and atomic transaction
     boundaries guarantee ACID durability without database corruption.
-}

-- | Record representing a failed structural proposal or verified evidence item.
--
-- See Note [Beam SQLite Relational Persistence and Concurrency Locking] [ref:note-beam-sqlite-persistence].
data EvidenceRecordT f = EvidenceRecord
  { evidenceId        :: Columnar f Int64
    -- ^ Unique primary key identifying this evidence record.
  , evidenceSig       :: Columnar f Text
    -- ^ Institution or module signature under which the verification occurred.
  , evidenceChangeRep :: Columnar f Text
    -- ^ Canonical structural AST representation of the change or synthesized patch.
  , evidenceReason    :: Columnar f Text
    -- ^ Human-readable diagnostic rationale, compiler diagnostic, or SMT outcome.
  , evidenceTimestamp :: Columnar f Int64
    -- ^ POSIX epoch timestamp (seconds) when the evidence was recorded.
  } deriving (Generic, Beamable)

type EvidenceRecord = EvidenceRecordT Identity
type EvidenceRecordId = PrimaryKey EvidenceRecordT Identity

deriving instance Show EvidenceRecord
deriving instance Eq EvidenceRecord

instance Table EvidenceRecordT where
  data PrimaryKey EvidenceRecordT f = EvidenceId (Columnar f Int64)
    deriving (Generic, Beamable)
  primaryKey = EvidenceId . evidenceId

deriving instance Show (PrimaryKey EvidenceRecordT Identity)
deriving instance Eq (PrimaryKey EvidenceRecordT Identity)

-- | Record representing a concrete counterexample (e.g. from Z3 or CEGIS)
-- linked to a failure evidence entry.
data CounterexampleRecordT f = CounterexampleRecord
  { counterexampleId          :: Columnar f Int64
    -- ^ Unique primary key identifying this counterexample witness.
  , counterexampleEvidenceRef :: PrimaryKey EvidenceRecordT f
    -- ^ Foreign key referencing the parent 'EvidenceRecordT' row.
  , counterexamplePayload     :: Columnar f Text
    -- ^ Serialized countermodel, variable assignment, or input witness triggering the failure.
  } deriving (Generic, Beamable)

type CounterexampleRecord = CounterexampleRecordT Identity
type CounterexampleRecordId = PrimaryKey CounterexampleRecordT Identity

deriving instance Show CounterexampleRecord
deriving instance Eq CounterexampleRecord

instance Table CounterexampleRecordT where
  data PrimaryKey CounterexampleRecordT f = CounterexampleId (Columnar f Int64)
    deriving (Generic, Beamable)
  primaryKey = CounterexampleId . counterexampleId

deriving instance Show (PrimaryKey CounterexampleRecordT Identity)
deriving instance Eq (PrimaryKey CounterexampleRecordT Identity)

-- | Record tracking autonomous synthesis / verification workflow runs.
data RunRecordT f = RunRecord
  { runId          :: Columnar f Int64
    -- ^ Unique primary key identifying this execution run.
  , runStatus      :: Columnar f Text
    -- ^ Operational lifecycle status (e.g., @"RUNNING"@, @"SUCCESS"@, @"FAILED_SANDBOX"@).
  , runStartedAt   :: Columnar f Int64
    -- ^ POSIX epoch timestamp (seconds) marking the initiation of the run.
  , runCompletedAt :: Columnar f (Maybe Int64)
    -- ^ POSIX epoch timestamp (seconds) marking the completion of the run, or 'Nothing' if still running.
  } deriving (Generic, Beamable)

type RunRecord = RunRecordT Identity
type RunRecordId = PrimaryKey RunRecordT Identity

deriving instance Show RunRecord
deriving instance Eq RunRecord

instance Table RunRecordT where
  data PrimaryKey RunRecordT f = RunId (Columnar f Int64)
    deriving (Generic, Beamable)
  primaryKey = RunId . runId

deriving instance Show (PrimaryKey RunRecordT Identity)
deriving instance Eq (PrimaryKey RunRecordT Identity)

-- | Master Evidence database schema containing evidence, counterexamples, and runs.
data EvidenceDb f = EvidenceDb
  { dbEvidence        :: f (TableEntity EvidenceRecordT)
    -- ^ Relational table entity storing verified and refuted evidence records.
  , dbCounterexamples :: f (TableEntity CounterexampleRecordT)
    -- ^ Relational table entity storing counterexample witnesses tied to evidence records.
  , dbRuns            :: f (TableEntity RunRecordT)
    -- ^ Relational table entity logging pipeline synthesis run lifecycles.
  } deriving (Generic, Database be)

-- | Default database settings configuration for EvidenceDb.
evidenceDb :: DatabaseSettings be EvidenceDb
evidenceDb = defaultDbSettings
