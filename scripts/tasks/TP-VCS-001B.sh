#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-VCS-001B] Setting up git-bundle-pure ==="

PKG_DIR="packages/git-bundle-pure"
mkdir -p "$PKG_DIR/src/Data/VCS"
mkdir -p "$PKG_DIR/test"

cat << 'EOF' > "$PKG_DIR/git-bundle-pure.cabal"
cabal-version:      3.0
name:               git-bundle-pure
version:            0.1.0.0
synopsis:           Pure-Haskell Git Object Hashing, PACK v2, and gitformat-bundle(5) Codec
description:        Standalone zero-FFI implementation of Git loose object hashing, PACK v2 encoding, and gitformat-bundle(5) v2 codec.
license:            BSD-3-Clause
author:             Nadia Yvette Chambers
maintainer:         nadia.yvette.chambers@ik.me
category:           Data, Development
build-type:         Simple

library
    exposed-modules:
        Data.VCS.GitBundle
    build-depends:
        base >= 4.18 && < 5,
        bytestring >= 0.10 && < 0.13,
        containers >= 0.6 && < 0.9,
        zlib >= 0.6 && < 0.8,
        cryptohash-sha1 >= 0.11 && < 0.12,
        base16-bytestring >= 1.0 && < 1.1
    hs-source-dirs:   src
    default-language: GHC2021
    ghc-options:      -Wall -O2

test-suite git-bundle-pure-test
    type:             exitcode-stdio-1.0
    main-is:          Main.hs
    hs-source-dirs:   test
    build-depends:
        base >= 4.18 && < 5,
        bytestring,
        git-bundle-pure,
        cryptohash-sha1
    default-language: GHC2021
    ghc-options:      -Wall
EOF

cat << 'EOF' > "$PKG_DIR/src/Data/VCS/GitBundle.hs"
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module Data.VCS.GitBundle
  ( OidHex (..)
  , GitObjType (..)
  , GitObject (..)
  , BundleRef (..)
  , GitBundleV2 (..)
  , hashGitObject
  , encodeObjHeader
  , encodePackV2
  , encodeGitBundleV2
  , decodeGitBundleV2Header
  ) where

import Codec.Compression.Zlib qualified as Zlib
import Crypto.Hash.SHA1 qualified as SHA1
import Data.Bits ( shiftL, shiftR, (.&.), (.|.) )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as B16
import Data.ByteString.Builder qualified as B
import Data.ByteString.Char8 qualified as C8
import Data.ByteString.Lazy qualified as BL
import Data.Word (Word32, Word8)
import GHC.Generics (Generic)

newtype OidHex = OidHex { unOidHex :: ByteString }
  deriving stock (Eq, Ord, Show, Generic)

data GitObjType
  = ObjCommit -- ^ Type 1
  | ObjTree   -- ^ Type 2
  | ObjBlob   -- ^ Type 3
  | ObjTag    -- ^ Type 4
  deriving stock (Eq, Ord, Show, Generic)

data GitObject = GitObject
  { goType    :: !GitObjType
  , goPayload :: !ByteString
  } deriving stock (Eq, Show, Generic)

data BundleRef = BundleRef
  { brOid     :: !OidHex
  , brRefName :: !ByteString
  } deriving stock (Eq, Show, Generic)

data GitBundleV2 = GitBundleV2
  { gbPrerequisites :: ![OidHex]
  , gbAdvertised    :: ![BundleRef]
  , gbObjects       :: ![GitObject]
  } deriving stock (Eq, Show, Generic)

-- | Computes canonical 40-hex-char Git SHA-1 OID ("<type> <len>\0<payload>").
hashGitObject :: GitObject -> OidHex
hashGitObject (GitObject ty payload) =
  let tyName = case ty of
        ObjCommit -> "commit"
        ObjTree   -> "tree"
        ObjBlob   -> "blob"
        ObjTag    -> "tag"
      hdr = tyName <> " " <> C8.pack (show (BS.length payload)) <> "\0"
  in OidHex (B16.encode (SHA1.hash (hdr <> payload)))

-- | Encodes the Git PACK v2 variable-length (type, uncompressedSize) header.
encodeObjHeader :: GitObjType -> Int -> ByteString
encodeObjHeader ty sz =
  let typeBits :: Word8
      typeBits = case ty of
        ObjCommit -> 1
        ObjTree   -> 2
        ObjBlob   -> 3
        ObjTag    -> 4
      firstLow4 = fromIntegral (sz .&. 0x0F) :: Word8
      rem0      = sz `shiftR` 4
      firstByte = (if rem0 > 0 then 0x80 else 0x00) .|. (typeBits `shiftL` 4) .|. firstLow4
      go 0   = []
      go val =
        let chunk = fromIntegral (val .&. 0x7F) :: Word8
            next  = val `shiftR` 7
            msb   = if next > 0 then 0x80 else 0x00
        in (msb .|. chunk) : go next
  in BS.pack (firstByte : go rem0)

-- | Serializes a list of GitObjects into a valid Git PACK v2 binary stream
--   with its trailing 20-byte raw SHA-1 checksum.
encodePackV2 :: [GitObject] -> ByteString
encodePackV2 objs =
  let count :: Word32
      count = fromIntegral (length objs)
      encodeOne (GitObject ty raw) =
        let hdr  = encodeObjHeader ty (BS.length raw)
            comp = BL.toStrict (Zlib.compress (BL.fromStrict raw))
        in B.byteString hdr <> B.byteString comp
      bodyBuilder =
        B.byteString "PACK"
        <> B.word32BE 2
        <> B.word32BE count
        <> foldMap encodeOne objs
      bodyBytes = BL.toStrict (B.toLazyByteString bodyBuilder)
      trailer   = SHA1.hash bodyBytes
  in bodyBytes <> trailer

-- | Serializes a complete v2 gitformat-bundle(5) archive.
encodeGitBundleV2 :: GitBundleV2 -> ByteString
encodeGitBundleV2 (GitBundleV2 prereqs refs objs) =
  let prereqLines = [ "-" <> unOidHex oid <> "\n" | oid <- prereqs ]
      refLines    = [ unOidHex r.brOid <> " " <> r.brRefName <> "\n" | r <- refs ]
      asciiHeader =
        BS.concat (["# v2 git bundle\n"] ++ prereqLines ++ refLines ++ ["\n"])
  in asciiHeader <> encodePackV2 objs

-- | Parses the ASCII header of a v2 gitformat-bundle(5), returning
--   (prerequisites, advertisedRefs, remainingPackBytes).
decodeGitBundleV2Header :: ByteString -> Either String ([OidHex], [BundleRef], ByteString)
decodeGitBundleV2Header raw =
  case C8.stripPrefix "# v2 git bundle\n" raw of
    Nothing   -> Left "Missing '# v2 git bundle' magic header"
    Just rest -> parseLines [] [] rest
  where
    parseLines prereqs refs bs =
      case C8.break (== '\n') bs of
        (line, afterNl)
          | BS.null line ->
              Right (reverse prereqs, reverse refs, BS.drop 1 afterNl)
          | Just oid <- C8.stripPrefix "-" line ->
              let cleanOid = fst (C8.break (== ' ') oid)
              in parseLines (OidHex cleanOid : prereqs) refs (BS.drop 1 afterNl)
          | otherwise ->
              let (oid, refRest) = C8.break (== ' ') line
                  refName        = BS.drop 1 refRest
              in parseLines prereqs (BundleRef (OidHex oid) refName : refs) (BS.drop 1 afterNl)
EOF

cat << 'EOF' > "$PKG_DIR/test/Main.hs"
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
EOF

if ! grep -q "packages/git-bundle-pure" cabal.project; then
  echo "  Adding git-bundle-pure to cabal.project..."
  sed -i '/packages\/darcs-witnesses/i \  packages\/git-bundle-pure' cabal.project
fi

echo "=== [TP-VCS-001B] Completed successfully ==="
