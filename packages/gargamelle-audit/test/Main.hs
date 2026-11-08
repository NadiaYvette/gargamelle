{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import qualified Data.Set as Set
import qualified Data.Text as T
import System.Directory (getTemporaryDirectory, removeFile)
import System.FilePath ((</>))
import Test.Tasty
import Test.Tasty.HUnit

import Gargamelle.Audit.Baseline
  ( evaluateRatchet
  , loadBaseline
  , saveBaseline
  )
import Gargamelle.Audit.Types
  ( AuditViolation (..)
  , BaselineFingerprints (..)
  , RatchetVerdict (..)
  , SubstrateMode (..)
  , ViolationCategory (..)
  , defaultAuditThresholds
  )
import Gargamelle.Audit.WorkingMemory
  ( analyzeHaskellSource
  )

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "gargamelle-audit tests"
  [ testWorkingMemoryAnalyzer
  , testParameterArityGate
  , testRatchetBaseline
  , testBaselinePersistence
  ]

--------------------------------------------------------------------------------
-- 1. Working Memory Peak Analyzer
--------------------------------------------------------------------------------

testWorkingMemoryAnalyzer :: TestTree
testWorkingMemoryAnalyzer = testGroup "Working Memory Peak Analyzer"
  [ testCase "20-line function with 8 simultaneously live bindings triggers WorkingMemoryPeakExceeded" $ do
      let src = T.unlines
            [ "module Test.Heavy where"
            , ""
            , "heavyFunction :: IO ()"
            , "heavyFunction = do"
            , "  v1 <- action1"
            , "  v2 <- action2"
            , "  v3 <- action3"
            , "  v4 <- action4"
            , "  v5 <- action5"
            , "  v6 <- action6"
            , "  v7 <- action7"
            , "  v8 <- action8"
            , "  pure ()"
            , "  pure ()"
            , "  pure ()"
            , "  pure ()"
            , "  pure ()"
            , "  pure ()"
            , "  pure ()"
            , "  pure ()"
            , "  pure ()"
            , "  useAll v1 v2 v3 v4 v5 v6 v7 v8"
            ]
          (mode, violations) = analyzeHaskellSource defaultAuditThresholds "test/Heavy.hs" src
      assertEqual "Should be StandardModule" StandardModule mode
      let wmErrors = [ v | v <- violations, case avCategory v of WorkingMemoryPeakExceeded {} -> True; _ -> False ]
      assertEqual "Should have exactly 1 WorkingMemoryPeakExceeded" 1 (length wmErrors)
      case map avCategory wmErrors of
        [WorkingMemoryPeakExceeded peak limit spanLinesCount] -> do
          assertEqual "Peak should be 8" 8 peak
          assertEqual "Limit should be 7" 7 limit
          assertEqual "Span lines should be 20" 20 spanLinesCount
        _ -> assertFailure "Expected WorkingMemoryPeakExceeded"

  , testCase "20-line function with 8 sequentially scoped non-overlapping bindings passes" $ do
      let src = T.unlines
            [ "module Test.Sequential where"
            , ""
            , "sequentialFunction :: IO ()"
            , "sequentialFunction = do"
            , "  v1 <- action1"
            , "  consume v1"
            , "  v2 <- action2"
            , "  consume v2"
            , "  v3 <- action3"
            , "  consume v3"
            , "  v4 <- action4"
            , "  consume v4"
            , "  v5 <- action5"
            , "  consume v5"
            , "  v6 <- action6"
            , "  consume v6"
            , "  v7 <- action7"
            , "  consume v7"
            , "  v8 <- action8"
            , "  consume v8"
            , "  pure ()"
            , "  pure ()"
            ]
          (mode, violations) = analyzeHaskellSource defaultAuditThresholds "test/Sequential.hs" src
      assertEqual "Should be StandardModule" StandardModule mode
      let wmErrors = [ v | v <- violations, case avCategory v of WorkingMemoryPeakExceeded {} -> True; _ -> False ]
      assertEqual "Should have 0 WorkingMemoryPeakExceeded" [] wmErrors
  ]

--------------------------------------------------------------------------------
-- 2. Parameter Arity Gate
--------------------------------------------------------------------------------

testParameterArityGate :: TestTree
testParameterArityGate = testGroup "Parameter Arity Gate"
  [ testCase "5-parameter function in MyPkg.Public triggers ExcessiveParameterArity" $ do
      let src = T.unlines
            [ "module MyPkg.Public (fiveParamFunc) where"
            , ""
            , "fiveParamFunc :: Int -> String -> Bool -> Double -> Char -> IO ()"
            , "fiveParamFunc a b c d e = pure ()"
            ]
          (mode, violations) = analyzeHaskellSource defaultAuditThresholds "src/MyPkg/Public.hs" src
      assertEqual "Should be StandardModule" StandardModule mode
      let arityErrors = [ v | v <- violations, case avCategory v of ExcessiveParameterArity {} -> True; _ -> False ]
      assertEqual "Should have 1 ExcessiveParameterArity" 1 (length arityErrors)
      case map avCategory arityErrors of
        [ExcessiveParameterArity count limit] -> do
          assertEqual "Parameter count should be 5" 5 count
          assertEqual "Limit should be 4" 4 limit
        _ -> assertFailure "Expected ExcessiveParameterArity"

  , testCase "Exact same 5-parameter signature in MyPkg.Internal is exempted" $ do
      let src = T.unlines
            [ "module MyPkg.Internal (fiveParamFunc) where"
            , ""
            , "fiveParamFunc :: Int -> String -> Bool -> Double -> Char -> IO ()"
            , "fiveParamFunc a b c d e = pure ()"
            ]
          (mode, violations) = analyzeHaskellSource defaultAuditThresholds "src/MyPkg/Internal.hs" src
      assertEqual "Should be SubstrateModule" SubstrateModule mode
      let arityErrors = [ v | v <- violations, case avCategory v of ExcessiveParameterArity {} -> True; _ -> False ]
      assertEqual "Should have 0 ExcessiveParameterArity in Internal module" [] arityErrors

  , testCase "Exact same signature in module with ANN pragma is exempted" $ do
      let src = T.unlines
            [ "{-# ANN module \"audit:substrate\" #-}"
            , "module MyPkg.Public (fiveParamFunc) where"
            , ""
            , "fiveParamFunc :: Int -> String -> Bool -> Double -> Char -> IO ()"
            , "fiveParamFunc a b c d e = pure ()"
            ]
          (mode, violations) = analyzeHaskellSource defaultAuditThresholds "src/MyPkg/Public.hs" src
      assertEqual "Should be SubstrateModule" SubstrateModule mode
      let arityErrors = [ v | v <- violations, case avCategory v of ExcessiveParameterArity {} -> True; _ -> False ]
      assertEqual "Should have 0 ExcessiveParameterArity with ANN pragma" [] arityErrors
  ]

--------------------------------------------------------------------------------
-- 3. Ratchet Baseline Engine
--------------------------------------------------------------------------------

testRatchetBaseline :: TestTree
testRatchetBaseline = testGroup "Ratchet Baseline Engine"
  [ testCase "evaluateRatchet grandfathers untouched violation but blocks touched file" $ do
      let violation = AuditViolation
            { avFilePath    = "src/MyPkg/Foo.hs"
            , avSymbol      = "badFunction"
            , avStartLine   = 10
            , avEndLine     = 30
            , avCategory    = WorkingMemoryPeakExceeded 8 7 21
            , avRemediation = "Decompose function"
            }
          fingerprint = (avFilePath violation, avSymbol violation, avCategory violation)
          baseline = BaselineFingerprints (Set.singleton fingerprint)

      -- Case A: Untouched file -> grandfathered
      let verdictUntouched = evaluateRatchet baseline Set.empty [violation]
      assertEqual "Blocking violations should be empty for untouched file" [] (rvBlockingViolations verdictUntouched)
      assertEqual "Grandfathered count should be 1" 1 (rvGrandfatheredCount verdictUntouched)
      assertEqual "Resolved baseline count should be 0" 0 (rvResolvedBaselineCount verdictUntouched)

      -- Case B: Touched file -> zero grandfathering, blocked!
      let verdictTouched = evaluateRatchet baseline (Set.singleton "src/MyPkg/Foo.hs") [violation]
      assertEqual "Blocking violations should contain the violation" [violation] (rvBlockingViolations verdictTouched)
      assertEqual "Grandfathered count should be 0 for touched file" 0 (rvGrandfatheredCount verdictTouched)
      assertEqual "Resolved baseline count should be 0" 0 (rvResolvedBaselineCount verdictTouched)

  , testCase "evaluateRatchet detects resolved baseline violations" $ do
      let fp1 = ("src/A.hs", "funcA", WorkingMemoryPeakExceeded 8 7 20)
          fp2 = ("src/B.hs", "funcB", ExcessiveParameterArity 5 4)
          baseline = BaselineFingerprints (Set.fromList [fp1, fp2])
          -- Only funcA is still present
          currentViolation = AuditViolation
            { avFilePath    = "src/A.hs"
            , avSymbol      = "funcA"
            , avStartLine   = 1
            , avEndLine     = 20
            , avCategory    = WorkingMemoryPeakExceeded 8 7 20
            , avRemediation = "Fix"
            }
          verdict = evaluateRatchet baseline Set.empty [currentViolation]
      assertEqual "Grandfathered count" 1 (rvGrandfatheredCount verdict)
      assertEqual "Resolved count should be 1 (funcB fixed)" 1 (rvResolvedBaselineCount verdict)
  ]

--------------------------------------------------------------------------------
-- 4. Baseline Persistence Roundtrip
--------------------------------------------------------------------------------

testBaselinePersistence :: TestTree
testBaselinePersistence = testGroup "Baseline Persistence"
  [ testCase "saveBaseline and loadBaseline roundtrip" $ do
      tmpDir <- getTemporaryDirectory
      let tmpPath = tmpDir </> "test-audit-baseline.json"
          violations =
            [ AuditViolation
                { avFilePath    = "src/Foo.hs"
                , avSymbol      = "foo"
                , avStartLine   = 1
                , avEndLine     = 25
                , avCategory    = WorkingMemoryPeakExceeded 8 7 25
                , avRemediation = "Decompose"
                }
            , AuditViolation
                { avFilePath    = "src/Bar.hs"
                , avSymbol      = "bar"
                , avStartLine   = 5
                , avEndLine     = 5
                , avCategory    = ExcessiveParameterArity 6 4
                , avRemediation = "Bundle into record"
                }
            ]
      saveBaseline tmpPath violations
      loaded <- loadBaseline tmpPath
      let expectedFps = Set.fromList
            [ ("src/Foo.hs", "foo", WorkingMemoryPeakExceeded 8 7 25)
            , ("src/Bar.hs", "bar", ExcessiveParameterArity 6 4)
            ]
      assertEqual "Loaded fingerprints must match saved" (BaselineFingerprints expectedFps) loaded
      removeFile tmpPath
  ]
