{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BlockArguments #-}

module Main (main) where

import Test.Hspec
import Data.IORef (newIORef, readIORef, writeIORef)
import qualified Data.Text as T
import System.Directory (doesDirectoryExist)
import Sandbox.Effect
import Sandbox.Handler

main :: IO ()
main = hspec do
  -- Tested against Note [Bubblewrap Namespace Isolation and Resource Limiting Boundaries] [ref:note-sandbox-bwrap-isolation]
  describe "Bubblewrap & Subprocess Sandbox Isolation" do
    it "configures conservative default resource limits" do
      limitTimeoutSeconds defaultLimits `shouldBe` 30
      limitMemoryMB defaultLimits `shouldBe` 1024

    it "executes deterministic mock sandbox operations" do
      let (code, stdout, stderr) = pureMockSandboxRun defaultLimits "/bin/echo" ["hello"]
      code `shouldBe` 0
      stdout `shouldBe` "mock-output-for-/bin/echo-with-1-args"
      stderr `shouldBe` ""

    it "allocates and reliably cleans up temporary sandbox directories" do
      dirRef <- newIORef ""
      res <- withTempSandboxDir "test-unit" $ \dir -> do
        writeIORef dirRef dir
        doesDirectoryExist dir `shouldReturn` True
        pure (42 :: Int)
      res `shouldBe` Right 42
      dirPath <- readIORef dirRef
      doesDirectoryExist dirPath `shouldReturn` False

    it "executes benign command under sandboxed environment" do
      (code, stdout, _stderr) <- executeSandboxed defaultLimits "echo" ["gargamelle-sandbox-ok"]
      code `shouldBe` 0
      T.strip stdout `shouldBe` "gargamelle-sandbox-ok"

    it "executes command in isolated working directory with Bubblewrap or fallback" do
      res <- withTempSandboxDir "bwrap-unit" $ \workDir -> do
        (code, stdout, _stderr) <- executeBubblewrapSandboxed defaultLimits workDir "echo" ["isolated-ok"]
        code `shouldBe` 0
        pure (T.strip stdout)
      res `shouldBe` Right "isolated-ok"
