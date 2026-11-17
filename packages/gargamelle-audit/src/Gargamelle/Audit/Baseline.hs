{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : Gargamelle.Audit.Baseline
Description : Architectural Ratchet Baseline Persistence & Comparison Engine
Copyright   : (c) Nadia Yvette Chambers, 2026
License     : EUPL-1.2

@purpose
Evaluates audit violations against baseline snapshots to enforce zero new regressions
on touched files while quarantining existing technical debt.

@behavior
Loads and persists JSON baseline fingerprints, partitions violations into new vs legacy,
and produces actionable RatchetVerdict results.

@theory
Software architectural ratchet (Fowler / Lehman) and non-regression invariant gates.

@contracts
Purity: Deterministic fingerprinting and set-partition comparison.

@pattern
Snapshot baseline comparator and ratchet gate.

@example
evaluateRatchet basePrints touchedFiles currentViolations
-}

module Gargamelle.Audit.Baseline
  ( evaluateRatchet
  , loadBaseline
  , saveBaseline
  ) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BL
import Data.List (partition)
import Data.Set (Set)
import qualified Data.Set as Set
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeDirectory)

import Gargamelle.Audit.Types
  ( AuditViolation (..)
  , BaselineFingerprints (..)
  , RatchetVerdict (..)
  )

-- | Evaluate audit violations against touched files and baseline fingerprints.
--
-- If @avFilePath@ is a member of @touchedFiles@, zero grandfathering applies:
-- every 'AuditViolation' in a touched file is placed into 'rvBlockingViolations'.
-- For untouched files, a violation is grandfathered if and only if
-- @(avFilePath, avSymbol, avCategory)@ exists in 'BaselineFingerprints'.
-- Any net-new violation is added to 'rvBlockingViolations'.
evaluateRatchet
  :: BaselineFingerprints
  -> Set FilePath
  -> [AuditViolation]
  -> RatchetVerdict
evaluateRatchet (BaselineFingerprints baselineSet) touchedFiles violations =
  let isTouched v = Set.member (avFilePath v) touchedFiles
      fingerprint v = (avFilePath v, avSymbol v, avCategory v)
      isGrandfathered v = not (isTouched v) && Set.member (fingerprint v) baselineSet
      (gfViolations, blockingViolations) = partition isGrandfathered violations
      currentFingerprints = Set.fromList (map fingerprint violations)
      resolvedCount = Set.size (Set.difference baselineSet currentFingerprints)
  in RatchetVerdict
      { rvBlockingViolations    = blockingViolations
      , rvGrandfatheredCount    = length gfViolations
      , rvResolvedBaselineCount = resolvedCount
      }

-- | Load baseline fingerprints from a JSON file.
-- If the file does not exist, returns an empty baseline.
loadBaseline :: FilePath -> IO BaselineFingerprints
loadBaseline fp = do
  exists <- doesFileExist fp
  if not exists
    then pure (BaselineFingerprints Set.empty)
    else do
      result <- Aeson.eitherDecodeFileStrict' fp
      case result of
        Left err -> fail $ "Failed to parse baseline from " ++ fp ++ ": " ++ err
        Right bf -> pure bf

-- | Save baseline fingerprints constructed from violations to a JSON file.
saveBaseline :: FilePath -> [AuditViolation] -> IO ()
saveBaseline fp violations = do
  let dir = takeDirectory fp
  createDirectoryIfMissing True dir
  let fps = BaselineFingerprints $ Set.fromList
        [ (avFilePath v, avSymbol v, avCategory v) | v <- violations ]
  BL.writeFile fp (Aeson.encode fps)
