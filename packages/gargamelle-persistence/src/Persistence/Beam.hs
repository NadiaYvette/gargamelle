{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Milestone M2: High-level Beam persistence operations for Evidence, Counterexamples, and Runs.
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

import Control.Monad (void)
import Data.Int (Int64)
import Data.Text (Text)
import Database.Beam
import Database.Beam.Sqlite
import Database.SQLite.Simple (Connection, execute_)
import Persistence.Schema

-- | Initialize SQLite database tables for Evidence, Counterexamples, and Runs
-- if they do not already exist.
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

-- | Insert a failure or verified evidence item into the store.
insertEvidenceRecord :: Connection -> Int64 -> Text -> Text -> Text -> Int64 -> IO ()
insertEvidenceRecord conn eid sig rep reason ts =
  runBeamSqlite conn $ runInsert $
    insert (dbEvidence evidenceDb) $
      insertValues [EvidenceRecord eid sig rep reason ts]

-- | Find an evidence entry by its structural representation string.
findEvidenceByRep :: Connection -> Text -> IO (Maybe EvidenceRecord)
findEvidenceByRep conn rep =
  runBeamSqlite conn $ runSelectReturningOne $ select $ do
    ev <- all_ (dbEvidence evidenceDb)
    guard_ (evidenceChangeRep ev ==. val_ rep)
    pure ev

-- | Retrieve all stored evidence records.
listAllEvidence :: Connection -> IO [EvidenceRecord]
listAllEvidence conn =
  runBeamSqlite conn $ runSelectReturningList $ select $
    all_ (dbEvidence evidenceDb)

-- | Insert a counterexample associated with a specific evidence item.
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

-- | Track the beginning of an autonomous execution run.
startRunRecord :: Connection -> Int64 -> Text -> Int64 -> IO ()
startRunRecord conn rid status startedAt =
  runBeamSqlite conn $ runInsert $
    insert (dbRuns evidenceDb) $
      insertValues [RunRecord rid status startedAt Nothing]

-- | Mark an autonomous execution run as completed with a timestamp.
completeRunRecord :: Connection -> Int64 -> Text -> Int64 -> IO ()
completeRunRecord conn rid status completedAt =
  runBeamSqlite conn $ runUpdate $
    update (dbRuns evidenceDb)
      (\r -> (runStatus r <-. val_ status) <> (runCompletedAt r <-. val_ (Just completedAt)))
      (\r -> runId r ==. val_ rid)
