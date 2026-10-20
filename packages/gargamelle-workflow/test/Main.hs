{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

module Main where

import Test.Hspec
import Control.Arrow (Kleisli(..), arr, (>>>))
import qualified Data.Text as T
import Database.SQLite.Simple (open, close)
import Database.Beam
import Database.Beam.Sqlite
import Persistence.Schema
import Persistence.Beam

import Effect.Handlers
import Effect.Rope

import Sandbox.Effect
import Sandbox.Handler
import Workflow.Synthesis
import System.Directory (doesDirectoryExist)
import System.FilePath ((</>))
import Data.TreeDiff (Expr(..))

main :: IO ()
main = hspec $ do
  describe "Institution framework" $ do
    it "can compile base modules" $ do
      True `shouldBe` True

  describe "Milestone M1: Kernmantle Effect Orchestration" $ do
    it "executes sequential Rope arrows under pure mock handlers" $ do
      let pipeline = logInfoRope "start-workflow"
                 >>> getRandomWordRope
                 >>> arr (+ 1)
      let (Kleisli runner) = runRope pipeline pureMockHandlers
      res <- case runner () of
        Right val -> pure val
        Left err  -> fail (T.unpack err)
      res `shouldBe` 43

    it "interprets read file strand via pure mock handlers without IO" $ do
      let pipeline = readFileRope "test.txt"
      let (Kleisli runner) = runRope pipeline pureMockHandlers
      res <- case runner () of
        Right (Right content) -> pure content
        _                     -> fail "Expected Right content"
      res `shouldBe` "mock-content-for-test.txt"

    it "interprets beam evidence query strand via mock handlers" $ do
      let pipeline = queryEvidenceRope "hash-12345"
      let (Kleisli runner) = runRope pipeline pureMockHandlers
      res <- case runner () of
        Right mVal -> pure mVal
        Left err   -> fail (T.unpack err)
      res `shouldBe` Just "mock-evidence-val"

    it "interprets sandbox command execution strand via mock handlers" $ do
      let pipeline = runSandboxRope "gcc" ["-Wall", "test.c"]
      let (Kleisli runner) = runRope pipeline pureMockHandlers
      res <- case runner () of
        Right (code, out, _) -> pure (code, out)
        Left err             -> fail (T.unpack err)
      res `shouldBe` (0, "mock-run-ok")

    it "performs config-time static analysis without running effects" $ do
      let reqs = inspectMantleRequirements pureMockHandlers
      reqLog reqs `shouldBe` True
      reqReadFile reqs `shouldBe` True
      reqSandbox reqs `shouldBe` True
      reqBeam reqs `shouldBe` True

    it "validates physical environment resources at config time without executing effects" $ do
      let validReqs = Requirements
            { reqLog = True, reqReadFile = False, reqWriteFile = False
            , reqSandbox = True, reqBeam = True, reqRandom = False, reqTimer = False
            }
      resValid <- validateWorkflowResources "/usr/bin/bwrap" "/tmp/test.db" validReqs
      resValid `shouldBe` Right ()

      resMissingSandbox <- validateWorkflowResources "/nonexistent/sandbox/bin" "/tmp/test.db" validReqs
      case resMissingSandbox of
        Left (err:_) -> err `shouldBe` "Sandbox binary missing: /nonexistent/sandbox/bin"
        Left [] -> expectationFailure "Expected error message list to be non-empty"
        Right () -> expectationFailure "Expected missing sandbox to be caught at config time"

      resMissingDbDir <- validateWorkflowResources "/usr/bin/bwrap" "/nonexistent_dir_xyz/test.db" validReqs
      case resMissingDbDir of
        Left (err:_) -> err `shouldBe` "Database directory does not exist: /nonexistent_dir_xyz"
        Left [] -> expectationFailure "Expected error message list to be non-empty"
        Right () -> expectationFailure "Expected missing DB directory to be caught at config time"

  describe "Milestone M2: Beam Persistence Layer" $ do
    it "initializes SQLite schema and roundtrips evidence records" $ do
      conn <- open ":memory:"
      initEvidenceDb conn
      insertEvidenceRecord conn 1 "Institution.FO" "diff-node-expr" "TypeError in signature matching" 1600000
      mEv <- findEvidenceByRep conn "diff-node-expr"
      fmap evidenceReason mEv `shouldBe` Just "TypeError in signature matching"
      fmap evidenceSig mEv `shouldBe` Just "Institution.FO"
      close conn

    it "persists and queries counterexamples associated with evidence" $ do
      conn <- open ":memory:"
      initEvidenceDb conn
      insertEvidenceRecord conn 1 "Institution.FO" "diff-node-expr" "TypeError in signature" 1600000
      insertCounterexample conn 101 1 "Z3 Model: x = -1 violating refinement clause"
      cxs <- findCounterexamplesFor conn 1
      case cxs of
        [cx] -> counterexamplePayload cx `shouldBe` "Z3 Model: x = -1 violating refinement clause"
        _    -> expectationFailure "Expected exactly 1 counterexample"
      close conn

    it "tracks autonomous synthesis run lifecycle" $ do
      conn <- open ":memory:"
      initEvidenceDb conn
      startRunRecord conn 42 "RUNNING" 1700000
      completeRunRecord conn 42 "SUCCESS" 1700050
      runs <- runBeamSqlite conn $ runSelectReturningOne $ select $ do
        r <- all_ (dbRuns evidenceDb)
        guard_ (runId r ==. val_ 42)
        pure r
      fmap runStatus runs `shouldBe` Just "SUCCESS"
      fmap runCompletedAt runs `shouldBe` Just (Just 1700050)
      close conn

    it "executes Rope arrow pipeline with Beam SQLite handlers in IO" $ do
      conn <- open ":memory:"
      initEvidenceDb conn
      insertEvidenceRecord conn 1 "Institution.FO" "target-rep-42" "MissingInstance Eq Foo" 1600000
      let handlers = beamSqliteHandlers conn
      let pipeline = queryEvidenceRope "target-rep-42"
                 >>> arr (\case
                       Just err -> "Found failure: " `T.append` err
                       Nothing  -> "No prior failure")
      let (Kleisli runner) = runRope pipeline handlers
      res <- runner ()
      res `shouldBe` "Found failure: MissingInstance Eq Foo"
      close conn

    it "persists and roundtrips records on physical SQLite disk file across handles" $ do
      res <- withTempSandboxDir "beam-disk-test" $ \dir -> do
        let dbFile = dir </> "evidence.sqlite"
        conn1 <- open dbFile
        initEvidenceDb conn1
        insertEvidenceRecord conn1 99 "Institution.FO" "disk-rep-99" "DiskPersistenceError" 1700100
        close conn1

        conn2 <- open dbFile
        recM <- findEvidenceByRep conn2 "disk-rep-99"
        close conn2
        pure recM
      case res of
        Right (Just recVal) -> do
          evidenceReason recVal `shouldBe` "DiskPersistenceError"
          evidenceChangeRep recVal `shouldBe` "disk-rep-99"
        _ -> expectationFailure "Expected physical SQLite record to be read from disk file"

  describe "Milestone M3: Sandbox Automation & Crem State Machine" $ do
    it "enforces resource limits in mock sandbox execution" $ do
      let limits = defaultLimits { limitTimeoutSeconds = 5 }
      limitTimeoutSeconds limits `shouldBe` 5
      let (code, out, _) = pureMockSandboxRun limits "ghc" ["-O2", "Test.hs"]
      code `shouldBe` 0
      out `shouldBe` "mock-output-for-ghc-with-2-args"

    it "allocates and automatically cleans up bracketed temp directory" $ do
      let prefix = "test-bracket"
      capturedDir <- withTempSandboxDir prefix $ \dir -> do
        existsDuring <- doesDirectoryExist dir
        existsDuring `shouldBe` True
        pure dir
      case capturedDir of
        Right dir -> do
          existsAfter <- doesDirectoryExist dir
          existsAfter `shouldBe` False
        Left err -> expectationFailure (T.unpack err)

    it "initializes Crem synthesis state machine in StatePropose" $ do
      let machine = createSynthesisMachine
      let (evt, machine') = stepSynthesis machine (CmdProposeCandidate "let x = 1 in x")
      evt `shouldBe` EvtCandidateProposed "let x = 1 in x"
      let (evt2, _) = stepSynthesis machine' (CmdRunSandbox (0, "Sandbox run OK", ""))
      evt2 `shouldBe` EvtSandboxCompleted (0, "Sandbox run OK")

    it "transitions through Crem synthesis loop and completes on non-similar candidate" $ do
      let machine = createSynthesisMachine
      let commands =
            [ CmdProposeCandidate "patch_candidate_v1"
            , CmdRunSandbox (0, "build success", "")
            , CmdEvaluateEvidence (Just "TypeError: expected Int, got Bool")
            , CmdCheckSimilarity False
            ]
      let (events, _) = runSynthesisBatch machine commands
      events `shouldBe`
        [ EvtCandidateProposed "patch_candidate_v1"
        , EvtSandboxCompleted (0, "build success")
        , EvtEvidenceRecorded "TypeError: expected Int, got Bool"
        , EvtSynthesisSucceeded "New valid candidate synthesized"
        ]

    it "transitions back to Propose state when similar failure is detected" $ do
      let machine = createSynthesisMachine
      let commands =
            [ CmdProposeCandidate "failing_patch"
            , CmdRunSandbox (0, "test failure", "")
            , CmdEvaluateEvidence (Just "Divergence")
            , CmdCheckSimilarity True
            , CmdProposeCandidate "retry_candidate_v2"
            ]
      let (events, _) = runSynthesisBatch machine commands
      events `shouldBe`
        [ EvtCandidateProposed "failing_patch"
        , EvtSandboxCompleted (0, "test failure")
        , EvtEvidenceRecorded "Divergence"
        , EvtSynthesisRetry "Similar known failure detected, proposing alternative"
        , EvtCandidateProposed "retry_candidate_v2"
        ]

    it "physically executes commands within Bubblewrap / subprocess isolation" $ do
      let limits = defaultLimits { limitTimeoutSeconds = 5 }
      (code, out, _) <- executeSandboxed limits "echo" ["grounded-bwrap-test"]
      code `shouldBe` 0
      T.strip out `shouldBe` "grounded-bwrap-test"

    it "enforces physical process execution inside dedicated isolated directory" $ do
      res <- withTempSandboxDir "bwrap-workdir" $ \dir -> do
        (code, out, _) <- executeBubblewrapSandboxed defaultLimits dir "pwd" []
        code `shouldBe` 0
        T.strip out `shouldBe` T.pack dir
      case res of
        Right () -> pure ()
        Left err -> expectationFailure (T.unpack err)

    it "computes AST structural similarity using TreeDiff expressions" $ do
      let astA = App "Module" [App "Func" [App "Var" []]]
      let astB = App "Module" [App "Func" [App "Var" []]]
      let astDifferent = App "Other" [App "Construct" []]

      computeExprSimilarity astA astB `shouldBe` 1.0
      isAstStructurallySimilar 0.8 astA astB `shouldBe` True
      isAstStructurallySimilar 0.8 astA astDifferent `shouldBe` False