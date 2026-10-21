{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import Test.Hspec
import Control.Arrow (Kleisli(..), arr, (>>>))
import Data.Text (Text)
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
import Gargamelle.Sheaf
import Algebra.Lattice (Lattice(..), BoundedMeetSemiLattice(..))

data ContractLevel = Unconstrained | StandardSecurity | HighIntegrity | Contradiction
  deriving (Eq, Ord, Show)

instance Lattice ContractLevel where
  (/\) = max
  (\/) = min

instance BoundedMeetSemiLattice ContractLevel where
  top = Unconstrained

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

    -- Tested against Note [Formally Verified Mealy Automata State Topology] [ref:note-crem-mealy-topology]
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

    -- Tested against Note [AST Tree-Diff Structural Similarity Heuristics] [ref:note-ast-structural-similarity]
    it "computes AST structural similarity using TreeDiff expressions" $ do
      let astA = App "Module" [App "Func" [App "Var" []]]
      let astB = App "Module" [App "Func" [App "Var" []]]
      let astDifferent = App "Other" [App "Construct" []]

      computeExprSimilarity astA astB `shouldBe` 1.0
      isAstStructurallySimilar 0.8 astA astB `shouldBe` True
      isAstStructurallySimilar 0.8 astA astDifferent `shouldBe` False

  -- Tested against Note [End-to-End Sheaf-Gated CEGIS Synthesis Loop] [ref:note-sheaf-gated-cegis-loop]
  describe "Phase 6: End-to-End Sheaf-Gated CEGIS Workflow" $ do
    it "transitions Crem Mealy state machine into StateSheafCheck and completes on harmonic section" $ do
      let machine = createSynthesisMachine
      let commands =
            [ CmdProposeCandidate "sheaf_patch_v1"
            , CmdRunSandbox (0, "compilation ok", "")
            , CmdEvaluateEvidence (Just "Sandbox clean pass; checking sheaves")
            , CmdCheckSimilarityWithSheaf False
            , CmdEvaluateSheaf True []
            ]
      let (events, _) = runSynthesisBatch machine commands
      events `shouldBe`
        [ EvtCandidateProposed "sheaf_patch_v1"
        , EvtSandboxCompleted (0, "compilation ok")
        , EvtEvidenceRecorded "Sandbox clean pass; checking sheaves"
        , EvtSimilarityChecked False
        , EvtSheafHarmonicVerified "Harmonic global section verified; H^1 = 0"
        ]

    it "transitions Crem machine back to StatePropose when H1 cohomological obstructions are reported" $ do
      let machine = createSynthesisMachine
      let obs = ["Boundary obstruction on edge e1: src=HighIntegrity /= tgt=StandardSecurity"]
      let commands =
            [ CmdProposeCandidate "incompatible_aspect_patch"
            , CmdRunSandbox (0, "compilation ok", "")
            , CmdEvaluateEvidence (Just "Evaluating interface boundaries")
            , CmdCheckSimilarityWithSheaf False
            , CmdEvaluateSheaf False obs
            , CmdProposeCandidate "repaired_aspect_patch"
            ]
      let (events, _) = runSynthesisBatch machine commands
      events `shouldBe`
        [ EvtCandidateProposed "incompatible_aspect_patch"
        , EvtSandboxCompleted (0, "compilation ok")
        , EvtEvidenceRecorded "Evaluating interface boundaries"
        , EvtSimilarityChecked False
        , EvtSheafObstructionsDetected obs
        , EvtCandidateProposed "repaired_aspect_patch"
        ]

    it "runs end-to-end Sheaf-Gated CEGIS verifying H0 global section into Beam SQLite" $ do
      conn <- open ":memory:"
      let (complex :: CellComplex Text Text) = fromEdges [("e1", "ModA", "ModB")]
      let sheaf = symmetricSheaf (\_ (c :: Text) -> c) (\_ e -> e)
      let spec = fromListCochain0 [("ModA", "ProtocolV2"), ("ModB", "ProtocolV2")]
      let config = SheafCEGISConfig
            { cegisDbConn        = conn
            , cegisRunId         = 201
            , cegisCandidateName = "candidate_harmonic_201"
            , cegisChangeRep     = "ast_rep_protocol_v2"
            , cegisSig           = "Institution.Protocol"
            , cegisLimits        = defaultLimits { limitTimeoutSeconds = 5 }
            , cegisSandboxCmd    = ("echo", ["synthesizing-clean"])
            , cegisComplex       = complex
            , cegisSheaf         = sheaf
            , cegisCandidateSpec = spec
            , cegisTimestamp     = 1800000
            }
      (outcome, events) <- runSheafGatedCEGIS config
      case outcome of
        SheafCEGISSuccess (GlobalSection sec) msg -> do
          msg `shouldBe` "Harmonic global section verified; H^1 = 0"
          lookupCochain0 "ModA" sec `shouldBe` Just "ProtocolV2"
          lookupCochain0 "ModB" sec `shouldBe` Just "ProtocolV2"
        _ -> expectationFailure "Expected SheafCEGISSuccess"

      length events `shouldBe` 5

      -- Verify Beam SQLite persistence of verified evidence and run lifecycle
      mEv <- findEvidenceByRep conn "ast_rep_protocol_v2"
      case mEv of
        Just ev -> evidenceReason ev `shouldBe` "Harmonic global section verified; H^1 = 0"
        Nothing -> expectationFailure "Expected verified evidence record in Beam SQLite"

      runs <- runBeamSqlite conn $ runSelectReturningOne $ select $ do
        r <- all_ (dbRuns evidenceDb)
        guard_ (runId r ==. val_ 201)
        pure r
      fmap runStatus runs `shouldBe` Just "SUCCESS"
      close conn

    it "runs end-to-end Sheaf-Gated CEGIS detecting H1 boundary obstructions and recording counterexamples" $ do
      conn <- open ":memory:"
      let (complex :: CellComplex Text Text) = fromEdges [("edge_api", "ServiceAuth", "ServiceBilling")]
      let sheaf = symmetricSheaf (\_ (c :: Text) -> c) (\_ e -> e)
      let spec = fromListCochain0 [("ServiceAuth", "AuthTokenBearer"), ("ServiceBilling", "OAuth2Secret")]
      let config = SheafCEGISConfig
            { cegisDbConn        = conn
            , cegisRunId         = 202
            , cegisCandidateName = "candidate_mismatch_202"
            , cegisChangeRep     = "ast_rep_mismatch_auth_billing"
            , cegisSig           = "Institution.Microservices"
            , cegisLimits        = defaultLimits { limitTimeoutSeconds = 5 }
            , cegisSandboxCmd    = ("echo", ["building-candidate"])
            , cegisComplex       = complex
            , cegisSheaf         = sheaf
            , cegisCandidateSpec = spec
            , cegisTimestamp     = 1800100
            }
      (outcome, events) <- runSheafGatedCEGIS config
      case outcome of
        SheafCEGISObstruction [obs] -> do
          obstructedEdge obs `shouldBe` "edge_api"
          sourceRestriction obs `shouldBe` "AuthTokenBearer"
          targetRestriction obs `shouldBe` "OAuth2Secret"
        _ -> expectationFailure "Expected SheafCEGISObstruction with 1 obstruction"

      length events `shouldBe` 5

      mEv <- findEvidenceByRep conn "ast_rep_mismatch_auth_billing"
      case mEv of
        Just ev -> do
          evidenceSig ev `shouldBe` "Institution.Microservices"
          T.isInfixOf "edge_api" (evidenceReason ev) `shouldBe` True
        Nothing -> expectationFailure "Expected obstruction evidence record in Beam SQLite"

      cxs <- findCounterexamplesFor conn (202 * 10)
      length cxs `shouldBe` 1

      runs <- runBeamSqlite conn $ runSelectReturningOne $ select $ do
        r <- all_ (dbRuns evidenceDb)
        guard_ (runId r ==. val_ 202)
        pure r
      fmap runStatus runs `shouldBe` Just "OBSTRUCTED_H1"
      close conn

    it "bypasses sandbox execution and immediately retries on cached Beam SQLite prior failure" $ do
      conn <- open ":memory:"
      initEvidenceDb conn
      insertEvidenceRecord conn 901 "Institution.FO" "known_broken_hash" "PriorTypeCheckMismatch" 1800050

      let (complex :: CellComplex Text Text) = fromEdges [("e1", "v1", "v2")]
      let sheaf = symmetricSheaf (\_ (c :: Text) -> c) (\_ e -> e)
      let spec = fromListCochain0 [("v1", "ContractA"), ("v2", "ContractA")]
      let config = SheafCEGISConfig
            { cegisDbConn        = conn
            , cegisRunId         = 203
            , cegisCandidateName = "candidate_cached_fail"
            , cegisChangeRep     = "known_broken_hash"
            , cegisSig           = "Institution.FO"
            , cegisLimits        = defaultLimits
            , cegisSandboxCmd    = ("false", [])
            , cegisComplex       = complex
            , cegisSheaf         = sheaf
            , cegisCandidateSpec = spec
            , cegisTimestamp     = 1800200
            }
      (outcome, events) <- runSheafGatedCEGIS config
      outcome `shouldBe` SheafCEGISPriorFailureFound "PriorTypeCheckMismatch"
      events `shouldBe`
        [ EvtCandidateProposed "candidate_cached_fail"
        , EvtSandboxCompleted (0, "cached-prior-check")
        , EvtEvidenceRecorded "PriorTypeCheckMismatch"
        , EvtSynthesisRetry "Similar known failure detected, proposing alternative"
        ]

      runs <- runBeamSqlite conn $ runSelectReturningOne $ select $ do
        r <- all_ (dbRuns evidenceDb)
        guard_ (runId r ==. val_ 203)
        pure r
      fmap runStatus runs `shouldBe` Just "RETRY_PRIOR_FAILURE"
      close conn

    it "reconciles boundary discrepancies via Knaster-Tarski Store diffusion during CEGIS" $ do
      conn <- open ":memory:"
      let (complex :: CellComplex Text Text) = fromEdges [("e1", "ModuleA", "ModuleB"), ("e2", "ModuleB", "ModuleC")]
      let sheaf = symmetricSheaf (\_ (c :: ContractLevel) -> c) (\_ e -> e)
      let initialSpec = fromListCochain0
            [ ("ModuleA", HighIntegrity)
            , ("ModuleB", StandardSecurity)
            , ("ModuleC", Unconstrained)
            ]

      let config = SheafCEGISConfig
            { cegisDbConn        = conn
            , cegisRunId         = 204
            , cegisCandidateName = "diffusing_contract_candidate"
            , cegisChangeRep     = "ast_rep_contract_diffusion"
            , cegisSig           = "Institution.Security"
            , cegisLimits        = defaultLimits { limitTimeoutSeconds = 5 }
            , cegisSandboxCmd    = ("echo", ["diffusion-ok"])
            , cegisComplex       = complex
            , cegisSheaf         = sheaf
            , cegisCandidateSpec = initialSpec
            , cegisTimestamp     = 1800300
            }
      (outcome, events) <- runSheafGatedCEGISWithDiffusion 10 config
      case outcome of
        SheafCEGISSuccess (GlobalSection sec) msg -> do
          msg `shouldBe` "Harmonic global section attained via cellular diffusion; H^1 = 0"
          lookupCochain0 "ModuleA" sec `shouldBe` Just HighIntegrity
          lookupCochain0 "ModuleB" sec `shouldBe` Just HighIntegrity
          lookupCochain0 "ModuleC" sec `shouldBe` Just HighIntegrity
        _ -> expectationFailure "Expected SheafCEGISSuccess via diffusion"

      length events `shouldBe` 5

      runs <- runBeamSqlite conn $ runSelectReturningOne $ select $ do
        r <- all_ (dbRuns evidenceDb)
        guard_ (runId r ==. val_ 204)
        pure r
      fmap runStatus runs `shouldBe` Just "SUCCESS_DIFFUSED"
      close conn
