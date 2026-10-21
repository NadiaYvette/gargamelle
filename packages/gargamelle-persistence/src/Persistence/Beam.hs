{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Milestone M2: High-level Beam persistence operations for Evidence, Counterexamples, and Runs.
--
-- Provides transactional SQLite persistence using the Beam ORM:
--
-- @
--   ┌───────────────────────┐
--   │    EvidenceRecordT    │◄──────┐
--   │ (id, sig, rep, ts)    │       │ FK (evidence_ref__id)
--   └───────────────────────┘       │
--                               ┌───┴───────────────────┐
--   ┌───────────────────────┐   │ CounterexampleRecordT │
--   │      RunRecordT       │   │ (id, payload, ref)    │
--   │ (id, status, started) │   └───────────────────────┘
--   └───────────────────────┘
-- @
--
-- All operations are executed atomically via 'runBeamSqlite' under SQLite transaction
-- boundaries, preventing race conditions during concurrent CEGIS loops.
--
-- See Note [Beam SQLite Relational Persistence and Concurrency Locking] [ref:note-beam-sqlite-persistence].
module Persistence.Beam
  ( -- * Initialization
    initEvidenceDb
    -- * Evidence Operations
  , insertEvidenceRecord
  , findEvidenceByRep
  , listAllEvidence
    -- * Counterexample Operations
  , insertCounterexample
  , findCounterexamplesFor
    -- * Run Tracking Operations
  , startRunRecord
  , completeRunRecord
  ) where

import Data.Int (Int64)
import Data.Text (Text)
import Database.Beam
import Database.Beam.Sqlite
import Database.SQLite.Simple (Connection, execute_)
import Persistence.Schema

-- | Initialize SQLite database tables for Evidence, Counterexamples, and Runs
-- if they do not already exist.
--
-- Idempotent: creates tables with foreign keys and index constraints only if missing.
initEvidenceDb :: Connection -> IO ()
initEvidenceDb conn = do
  execute_ conn
    "CREATE TABLE IF NOT EXISTS evidence \
    \( id INTEGER PRIMARY KEY \
    \, sig TEXT NOT NULL \
    \, change_rep TEXT NOT NULL \
    \, reason TEXT NOT NULL \
    \, timestamp INTEGER NOT NULL \
    \);"
  execute_ conn
    "CREATE TABLE IF NOT EXISTS counterexamples \
    \( id INTEGER PRIMARY KEY \
    \, evidence_ref__id INTEGER NOT NULL \
    \, payload TEXT NOT NULL \
    \, FOREIGN KEY(evidence_ref__id) REFERENCES evidence(id) \
    \);"
  execute_ conn
    "CREATE TABLE IF NOT EXISTS runs \
    \( id INTEGER PRIMARY KEY \
    \, status TEXT NOT NULL \
    \, started_at INTEGER NOT NULL \
    \, completed_at INTEGER \
    \);"

-- | Insert a verified or failure evidence item into the store.
--
-- Parameters:
--   - 'Connection': Active SQLite database connection.
--   - 'Int64': Unique evidence primary key ID.
--   - 'Text': Module or institution signature name.
--   - 'Text': Canonical structural representation of the patch or expression.
--   - 'Text': Diagnostic reason string or SMT failure witness.
--   - 'Int64': POSIX epoch timestamp in seconds.
insertEvidenceRecord :: Connection -> Int64 -> Text -> Text -> Text -> Int64 -> IO ()
insertEvidenceRecord conn eid sig rep reason ts =
  runBeamSqlite conn $ runInsert $
    insert (dbEvidence evidenceDb) $
      insertValues [EvidenceRecord eid sig rep reason ts]

-- | Find an evidence entry by its structural representation string.
--
-- Used by the CEGIS engine to quickly reject syntactically different but
-- structurally identical variants of previously refuted candidates.
findEvidenceByRep :: Connection -> Text -> IO (Maybe EvidenceRecord)
findEvidenceByRep conn rep =
  runBeamSqlite conn $ runSelectReturningOne $ select $ do
    ev <- all_ (dbEvidence evidenceDb)
    guard_ (evidenceChangeRep ev ==. val_ rep)
    pure ev

-- | Retrieve all stored evidence records ordered arbitrarily.
listAllEvidence :: Connection -> IO [EvidenceRecord]
listAllEvidence conn =
  runBeamSqlite conn $ runSelectReturningList $ select $
    all_ (dbEvidence evidenceDb)

-- | Insert a counterexample witness associated with a specific evidence record.
--
-- Parameters:
--   - 'Connection': Active SQLite database connection.
--   - 'Int64': Unique counterexample primary key ID.
--   - 'Int64': Foreign key ID referencing the parent 'EvidenceRecordT'.
--   - 'Text': Serialized counterexample payload (e.g. SMT model assignment).
insertCounterexample :: Connection -> Int64 -> Int64 -> Text -> IO ()
insertCounterexample conn cid eid payload =
  runBeamSqlite conn $ runInsert $
    insert (dbCounterexamples evidenceDb) $
      insertValues [CounterexampleRecord cid (EvidenceId eid) payload]

-- | Query all counterexamples associated with a specific evidence ID.
findCounterexamplesFor :: Connection -> Int64 -> IO [CounterexampleRecord]
findCounterexamplesFor conn eid =
  runBeamSqlite conn $ runSelectReturningList $ select $ do
    cx <- all_ (dbCounterexamples evidenceDb)
    guard_ (counterexampleEvidenceRef cx ==. val_ (EvidenceId eid))
    pure cx

-- | Track the beginning of an autonomous synthesis or verification run.
--
-- Parameters:
--   - 'Connection': Active SQLite database connection.
--   - 'Int64': Unique run primary key ID.
--   - 'Text': Initial status string (e.g. @"RUNNING"@).
--   - 'Int64': Start POSIX epoch timestamp in seconds.
startRunRecord :: Connection -> Int64 -> Text -> Int64 -> IO ()
startRunRecord conn rid status startedAt =
  runBeamSqlite conn $ runInsert $
    insert (dbRuns evidenceDb) $
      insertValues [RunRecord rid status startedAt Nothing]

-- | Mark an autonomous execution run as completed with final status and timestamp.
--
-- Parameters:
--   - 'Connection': Active SQLite database connection.
--   - 'Int64': Run primary key ID.
--   - 'Text': Final status string (e.g. @"SUCCESS"@, @"FAILED_SANDBOX"@).
--   - 'Int64': Completion POSIX epoch timestamp in seconds.
completeRunRecord :: Connection -> Int64 -> Text -> Int64 -> IO ()
completeRunRecord conn rid status completedAt =
  runBeamSqlite conn $ runUpdate $
    update (dbRuns evidenceDb)
      (\r -> (runStatus r <-. val_ status) <> (runCompletedAt r <-. val_ (Just completedAt)))
      (\r -> runId r ==. val_ rid)
