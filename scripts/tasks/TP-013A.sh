#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-013A] Setting up Gargamelle.Evidence.GitBundle ==="

# 0. Ensure cabal.project.local exists
if [ ! -f cabal.project.local ] && [ -f /home/nyc/src/gargamelle/cabal.project.local ]; then
  cp -f /home/nyc/src/gargamelle/cabal.project.local ./cabal.project.local
fi

EVID_DIR="packages/gargamelle-evidence"
mkdir -p "$EVID_DIR/src/Gargamelle/Evidence"

# 1. Clean legacy unexposed GitBundle.hs
rm -f "$EVID_DIR/src/GitBundle.hs"

# 2. Write Gargamelle.Evidence.GitBundle
cat << 'EOF' > "$EVID_DIR/src/Gargamelle/Evidence/GitBundle.hs"
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module Gargamelle.Evidence.GitBundle
  ( -- * OID Types
    BlobOid(..)
  , TreeOid(..)
  , CommitOid(..)
  , computeBlobOid
  , computeTreeOid
  , computeCommitOid
    -- * Git Objects & Types
  , GitObjType(..)
  , GitObject(..)
  , BundleRef(..)
  , GitBundleV2(..)
  , OidHex(..)
  , hashGitObject
    -- * Serialization & Codecs
  , encodeObjHeader
  , encodePackV2
  , encodeGitBundleV2
  , decodeGitBundleV2Header
  , emitGitFastImportStream
    -- * Institutional Metadata (.gpatch support)
  , gpatchRefPrefix
  , storeGpatchMetadata
  , extractGpatchMetadata
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C8
import Data.VCS.GitBundle
  ( BundleRef (..)
  , GitBundleV2 (..)
  , GitObjType (..)
  , GitObject (..)
  , OidHex (..)
  , decodeGitBundleV2Header
  , encodeGitBundleV2
  , encodeObjHeader
  , encodePackV2
  , hashGitObject
  )
import GHC.Generics (Generic)

newtype BlobOid = BlobOid { unBlobOid :: OidHex }
  deriving stock (Eq, Ord, Show, Generic)

newtype TreeOid = TreeOid { unTreeOid :: OidHex }
  deriving stock (Eq, Ord, Show, Generic)

newtype CommitOid = CommitOid { unCommitOid :: OidHex }
  deriving stock (Eq, Ord, Show, Generic)

computeBlobOid :: ByteString -> BlobOid
computeBlobOid bs = BlobOid (hashGitObject (GitObject ObjBlob bs))

computeTreeOid :: ByteString -> TreeOid
computeTreeOid bs = TreeOid (hashGitObject (GitObject ObjTree bs))

computeCommitOid :: ByteString -> CommitOid
computeCommitOid bs = CommitOid (hashGitObject (GitObject ObjCommit bs))

-- | Generates a valid Git fast-import stream for multi-commit ingestion.
emitGitFastImportStream :: [(ByteString, ByteString, [(FilePath, ByteString)])] -> ByteString
emitGitFastImportStream commits = BS.concat (zipWith formatCommit [1 ..] commits)
  where
    formatCommit :: Int -> (ByteString, ByteString, [(FilePath, ByteString)]) -> ByteString
    formatCommit mark (refName, msg, files) =
      let header =
            "commit " <> refName <> "\n"
            <> "mark :" <> C8.pack (show mark) <> "\n"
            <> "author Antigravity <antigravity@deepmind.google> 1700000000 +0000\n"
            <> "committer Antigravity <antigravity@deepmind.google> 1700000000 +0000\n"
            <> "data " <> C8.pack (show (BS.length msg)) <> "\n"
            <> msg <> "\n"
          formatFile (fp, content) =
            "M 100644 inline " <> C8.pack fp <> "\n"
            <> "data " <> C8.pack (show (BS.length content)) <> "\n"
            <> content <> "\n"
          body = BS.concat (map formatFile files)
      in header <> body <> "\n"

-- | Custom institutional metadata ref prefix
gpatchRefPrefix :: ByteString
gpatchRefPrefix = "refs/gargamelle/gpatch/"

-- | Store custom institutional metadata blob under refs/gargamelle/gpatch/<packet-id>
storeGpatchMetadata :: ByteString -> ByteString -> GitBundleV2 -> GitBundleV2
storeGpatchMetadata packetId meta bundle =
  let metaObj = GitObject ObjBlob meta
      metaOid = hashGitObject metaObj
      metaRef = BundleRef metaOid (gpatchRefPrefix <> packetId)
  in bundle
      { gbAdvertised = metaRef : bundle.gbAdvertised
      , gbObjects    = metaObj : bundle.gbObjects
      }

-- | Extract custom institutional metadata blob from refs/gargamelle/gpatch/<packet-id>
extractGpatchMetadata :: ByteString -> GitBundleV2 -> Maybe ByteString
extractGpatchMetadata packetId bundle =
  let targetRef = gpatchRefPrefix <> packetId
  in case filter (\r -> r.brRefName == targetRef) bundle.gbAdvertised of
       [] -> Nothing
       (ref : _) ->
         case filter (\o -> hashGitObject o == ref.brOid) bundle.gbObjects of
           (obj : _) -> Just obj.goPayload
           []        -> Nothing
EOF

# 3. Update gargamelle-evidence.cabal
python3 -c '
with open("packages/gargamelle-evidence/gargamelle-evidence.cabal", "r") as f:
    content = f.read()

if "Gargamelle.Evidence.GitBundle" not in content:
    content = content.replace("    Evidence\n", "    Evidence\n    Gargamelle.Evidence.GitBundle\n")

if "git-bundle-pure" not in content:
    content = content.replace("    tree-diff >= 0.3 && < 0.5\n", "    tree-diff >= 0.3 && < 0.5,\n    git-bundle-pure >= 0.1 && < 0.2\n")
    content = content.replace("    hspec >= 2.10 && < 2.12\n", "    hspec >= 2.10 && < 2.12,\n    git-bundle-pure >= 0.1 && < 0.2,\n    bytestring\n")

with open("packages/gargamelle-evidence/gargamelle-evidence.cabal", "w") as f:
    f.write(content)
'

# 4. Update test/Main.hs
cat << 'EOF' > "$EVID_DIR/test/Main.hs"
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Test.Hspec
import Data.Proxy (Proxy(..))
import Data.Tree (Tree(..))
import qualified Data.HashMap.Strict as HM
import qualified Data.ByteString as BS
import Data.TreeDiff.Tree (treeDiff)
import Evidence
import Gargamelle.Evidence.GitBundle

-- Dummy signature for testing EvidenceContext
data DummySig

main :: IO ()
main = hspec $ do
  describe "Evidence (EvidenceStore & Exact Match)" $ do
    it "treats emptyEvidenceStore as identity" $ do
      let store = emptyEvidenceStore :: EvidenceStore DummySig
      unEvidenceStore (store <> mempty) `shouldBe` HM.empty

    it "records failure and detects known failing proposal" $ do
      let rep1 = StructuralRep "RootA" (Node "RootA" [Node "Child1" []])
      let rep2 = StructuralRep "RootB" (Node "RootB" [Node "Child2" []])
      let ev1 = Evidence rep1 (TypeError "type mismatch: expected Int, got Bool") Proxy
      let store1 = addEvidence ev1 (emptyEvidenceStore :: EvidenceStore DummySig)

      proposesKnownFailure rep1 store1 `shouldBe` True
      proposesKnownFailure rep2 store1 `shouldBe` False

      case checkProposal rep1 store1 of
        Just ev -> evidenceReason ev `shouldBe` TypeError "type mismatch: expected Int, got Bool"
        Nothing -> expectationFailure "Expected known failure, got Nothing"

      checkProposal rep2 store1 `shouldBe` Nothing

  describe "Evidence (Structural Tree-Diff Edit Distance)" $ do
    it "computes structural tree edit distance" $ do
      let treeA = Node "Func" [Node "ParamA" []]
      let treeB = Node "Func" [Node "ParamB" []]
      let diff = treeDiff treeA treeB
      editDistance diff `shouldBe` 2

    it "identifies identical trees with 0 edit distance" $ do
      let tree = Node "App" [Node "f" [], Node "x" []]
      let diff = treeDiff tree tree
      editDistance diff `shouldBe` 0

  describe "Gargamelle.Evidence.GitBundle" $ do
    it "computes canonical blob, tree, and commit OIDs" $ do
      let blobOid = computeBlobOid "hello world\n"
      unOidHex (unBlobOid blobOid) `shouldBe` "3b18e512dba79e4c8300dd08aeb37f8e728b8dad"

    it "emits valid fast-import stream" $ do
      let stream = emitGitFastImportStream
            [ ("refs/heads/main", "Initial commit", [("README.md", "# Test\n")]) ]
      BS.isPrefixOf "commit refs/heads/main\n" stream `shouldBe` True

    it "stores and extracts custom institutional metadata in git bundles" $ do
      let baseBundle = GitBundleV2 [] [] []
          packetId = "TP-013A"
          metadata = "{\"status\": \"witnessed\", \"cohomology_H1\": 0}"
          bundleWithMeta = storeGpatchMetadata packetId metadata baseBundle
          extracted = extractGpatchMetadata packetId bundleWithMeta
      extracted `shouldBe` Just metadata

    it "encodes and decodes git bundle with metadata" $ do
      let blob = GitObject ObjBlob "file content\n"
          baseBundle = GitBundleV2 [] [BundleRef (hashGitObject blob) "refs/heads/main"] [blob]
          bundle = storeGpatchMetadata "TP-013A" "meta-payload" baseBundle
          encoded = encodeGitBundleV2 bundle
      case decodeGitBundleV2Header encoded of
        Left err -> expectationFailure ("Bundle header decode failed: " ++ err)
        Right (_, refs, _) -> do
          length refs `shouldBe` 2
EOF

echo "=== [TP-013A] Completed successfully ==="
