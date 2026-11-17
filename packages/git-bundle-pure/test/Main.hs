{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (unless)
import Crypto.Hash.SHA1 qualified as SHA1
import Data.ByteString qualified as BS
import Data.VCS.GitBundle
import System.Exit (exitFailure, exitSuccess)

main :: IO ()
main = do
  putStrLn "Running git-bundle-pure test suite..."

  -- 1. Test canonical Git blob hash
  let blobObj = GitObject ObjBlob "hello world\n"
      expectedBlobHash = "3b18e512dba79e4c8300dd08aeb37f8e728b8dad"
  unless (unOidHex (hashGitObject blobObj) == expectedBlobHash) $ do
    putStrLn "Failed: blob hash mismatch"
    exitFailure

  -- 2. Construct bundle
  let prereq = OidHex "0000000000000000000000000000000000000001"
      ref1   = BundleRef (OidHex expectedBlobHash) "refs/heads/main"
      ref2   = BundleRef (OidHex expectedBlobHash) "refs/gargamelle/gpatch/TP-VCS-001B"
      bundle = GitBundleV2 [prereq] [ref1, ref2] [blobObj]
      bundleBytes = encodeGitBundleV2 bundle

  -- 3. Parse bundle header
  case decodeGitBundleV2Header bundleBytes of
    Left err -> do
      putStrLn ("Failed to decode bundle header: " ++ err)
      exitFailure
    Right (prereqs, refs, packBytes) -> do
      unless (prereqs == [prereq]) $ do
        putStrLn "Prerequisites mismatch"
        exitFailure
      unless (refs == [ref1, ref2]) $ do
        putStrLn "Advertised refs mismatch"
        exitFailure
      -- 4. Check PACK v2 header & 20-byte SHA-1 trailer
      unless (BS.take 4 packBytes == "PACK") $ do
        putStrLn "Pack magic missing"
        exitFailure
      let packLen = BS.length packBytes
      unless (packLen >= 32) $ do
        putStrLn "Pack too short"
        exitFailure
      let (packBody, packTrailer) = BS.splitAt (packLen - 20) packBytes
          computedTrailer = SHA1.hash packBody
      unless (packTrailer == computedTrailer) $ do
        putStrLn "Pack checksum trailer mismatch"
        exitFailure

  putStrLn "All git-bundle-pure tests passed successfully."
  exitSuccess
