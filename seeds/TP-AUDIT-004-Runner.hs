{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : Gargamelle.Audit.Runner
Description : Complete Audit Scanner, Ratchet Evaluator, & Self-Test Driver
Copyright   : (c) Nadia Yvette Chambers, 2026
License     : EUPL-1.2

@purpose
Provides recursive filesystem traversal, AST/markdown analyzer orchestration,
and ratchet baseline comparison for the gargamelle-audit CLI.

@behavior
Scans packages and docs, applies WorkingMemory/DocTier/ApiGraph/Pedagogy checks,
and evaluates ratchet verdicts against .audit-baseline.json.

@theory
Zero-regression architectural ratchet gate.

@contracts
Total filesystem traversal with graceful file handling.

@pattern
Pipeline: Discover -> Analyze -> Ratchet -> Format -> ExitCode.

@example
runAuditCheck (Just ".") (Just ".audit-baseline.json") [] False
-}

module Gargamelle.Audit.Runner
  ( runAuditCheck
  , runAuditBaseline
  , runSelfTest
  ) where

import Data.List (isSuffixOf)
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory
  ( doesDirectoryExist
  , doesFileExist
  , listDirectory
  )
import System.Exit (ExitCode (..))
import System.FilePath ((</>))

import Gargamelle.Audit.ApiGraph (verifyApiExplorationGraph)
import Gargamelle.Audit.Baseline
  ( evaluateRatchet
  , loadBaseline
  , saveBaseline
  )
import Gargamelle.Audit.DocTier (checkModuleHeader, verifyModuleDocs)
import Gargamelle.Audit.Pedagogy (verifyDocumentationCorpus)
import Gargamelle.Audit.Repair (buildRepairPacket, yrpPromptPayload)
import Gargamelle.Audit.Types
  ( AuditViolation (..)
  , BaselineFingerprints (..)
  , RatchetVerdict (..)
  , defaultAuditThresholds
  )
import Gargamelle.Audit.WorkingMemory (analyzeHaskellSource)

-- | Run the full audit check command.
runAuditCheck :: Maybe FilePath -> Maybe FilePath -> [FilePath] -> Bool -> IO ExitCode
runAuditCheck mRoot mBaseline touched jsonRepair = do
  let root = maybe "." id mRoot
      baselineFile = maybe (root </> ".audit-baseline.json") id mBaseline
  hasBaseline <- doesFileExist baselineFile
  baseline <- if hasBaseline
                then loadBaseline baselineFile
                else pure (BaselineFingerprints Set.empty)

  violations <- scanCorpus root
  let touchedSet = Set.fromList touched
      verdict = evaluateRatchet baseline touchedSet violations
      blocking = rvBlockingViolations verdict

  if jsonRepair
    then do
      let packet = buildRepairPacket verdict
      TIO.putStrLn (yrpPromptPayload packet)
    else do
      putStrLn $ "=== [gargamelle-audit] Ratchet Verification Summary ==="
      putStrLn $ "  Total Violations Scanned: " ++ show (length violations)
      putStrLn $ "  Grandfathered Baseline:   " ++ show (rvGrandfatheredCount verdict)
      putStrLn $ "  Resolved Baseline Items:  " ++ show (rvResolvedBaselineCount verdict)
      putStrLn $ "  Blocking Violations:      " ++ show (length blocking)
      forM_ blocking $ \v -> do
        putStrLn $ "  [BLOCK] " ++ avFilePath v ++ ":" ++ show (avStartLine v) ++ " (" ++ T.unpack (avSymbol v) ++ ") " ++ T.unpack (avRemediation v)

  if null blocking
    then pure ExitSuccess
    else pure (ExitFailure 1)
  where
    forM_ = flip mapM_

-- | Run the baseline snapshot command.
runAuditBaseline :: Maybe FilePath -> Maybe FilePath -> IO ExitCode
runAuditBaseline mRoot mOutput = do
  let root = maybe "." id mRoot
      outFile = maybe (root </> ".audit-baseline.json") id mOutput
  violations <- scanCorpus root
  saveBaseline outFile violations
  putStrLn $ "=== [gargamelle-audit] Recorded " ++ show (length violations) ++ " baseline violations to " ++ outFile ++ " ==="
  pure ExitSuccess

-- | Internal self-test verifying packages/gargamelle-audit/src/ passes with 0 blocking violations.
runSelfTest :: IO ExitCode
runSelfTest = do
  let auditSrc = "packages" </> "gargamelle-audit" </> "src"
  exists <- doesDirectoryExist auditSrc
  if not exists
    then do
      putStrLn "Error: packages/gargamelle-audit/src directory not found for self-test"
      pure (ExitFailure 1)
    else do
      hsFiles <- findFilesWithExt ".hs" auditSrc
      violations <- concatMapM analyzeModule hsFiles
      if null violations
        then do
          putStrLn "=== [gargamelle-audit] Self-Test PASSED: zero blocking violations in gargamelle-audit/src! ==="
          pure ExitSuccess
        else do
          putStrLn $ "=== [gargamelle-audit] Self-Test FAILED: " ++ show (length violations) ++ " violation(s) found: ==="
          forM_ violations $ \v ->
            putStrLn $ "  - " ++ avFilePath v ++ ":" ++ show (avStartLine v) ++ " (" ++ T.unpack (avSymbol v) ++ ") " ++ T.unpack (avRemediation v)
          pure (ExitFailure 1)
  where
    concatMapM f xs = mapM f xs >>= pure . concat
    forM_ = flip mapM_
    analyzeModule fp = do
      content <- TIO.readFile fp
      let (mode, wmViols) = analyzeHaskellSource defaultAuditThresholds fp content
      let headerViols = checkModuleHeader mode fp (T.lines content)
      pure (wmViols ++ headerViols)

-- | Scan entire codebase packages and docs.
scanCorpus :: FilePath -> IO [AuditViolation]
scanCorpus root = do
  let pkgsDir = root </> "packages"
      docsDir = root </> "docs"
  hsFiles <- doesDirectoryExist pkgsDir >>= \case
    True  -> findFilesWithExt ".hs" pkgsDir
    False -> pure []
  mdFiles <- doesDirectoryExist docsDir >>= \case
    True  -> findFilesWithExt ".md" docsDir
    False -> pure []

  hsViolations <- concatMapM analyzeHsFile hsFiles
  docTuples <- mapM (\fp -> TIO.readFile fp >>= \c -> pure (fp, c)) mdFiles
  let pedViolations = verifyDocumentationCorpus defaultAuditThresholds docsDir docTuples
  pure (hsViolations ++ pedViolations)
  where
    concatMapM f xs = mapM f xs >>= pure . concat
    analyzeHsFile fp = do
      content <- TIO.readFile fp
      let (mode, wmViols) = analyzeHaskellSource defaultAuditThresholds fp content
      let docViols = verifyModuleDocs defaultAuditThresholds mode fp content
      let apiViols = verifyApiExplorationGraph defaultAuditThresholds mode fp content
      pure (wmViols ++ docViols ++ apiViols)

findFilesWithExt :: String -> FilePath -> IO [FilePath]
findFilesWithExt ext dir = do
  entries <- listDirectory dir
  subFiles <- mapM checkEntry entries
  pure (concat subFiles)
  where
    checkEntry name
      | name `elem` [".git", ".ok", "dist-newstyle", ".contextful", ".yamaarashi"] = pure []
      | otherwise = do
          let p = dir </> name
          isDir <- doesDirectoryExist p
          if isDir
            then findFilesWithExt ext p
            else if ext `isSuffixOf` name
              then pure [p]
              else pure []
