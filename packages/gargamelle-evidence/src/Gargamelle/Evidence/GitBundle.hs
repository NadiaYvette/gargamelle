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
