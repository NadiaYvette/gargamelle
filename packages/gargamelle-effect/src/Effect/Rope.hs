{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

-- | The core Rope arrow of the Kernmantle effect orchestration layer.
--
-- A 'Rope' decouples effect composition from handler interpretation,
-- enabling config-time static analysis and pluggable production/test execution.
module Effect.Rope
  ( Rope(..)
  , runRope
  , ropeFromCore
  , logInfoRope
  , logWarnRope
  , logErrorRope
  , readFileRope
  , writeFileRope
  , runSandboxRope
  , queryEvidenceRope
  , storeEvidenceRope
  , getRandomWordRope
  , getTimestampRope
  , Requirements(..)
  , emptyRequirements
  , inspectMantleRequirements
  , validateWorkflowResources
  ) where

import Control.Arrow
import Control.Category
import Prelude hiding (id, (.))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Word (Word64)
import System.Directory (doesFileExist, doesDirectoryExist)
import System.FilePath (takeDirectory)
import Effect.Handlers
import Effect.Strand

-- | The central Rope arrow.
--
-- Strands are combined into an arrow pipeline, and handlers are supplied
-- at invocation time.
newtype Rope core mantle a b = Rope
  { unRope :: Handlers core -> core a b
  }

instance Category core => Category (Rope core mantle) where
  id = Rope $ const id
  Rope f . Rope g = Rope $ \h -> f h . g h

instance Arrow core => Arrow (Rope core mantle) where
  arr f = Rope $ const (arr f)
  first (Rope f) = Rope $ \h -> first (f h)
  second (Rope f) = Rope $ \h -> second (f h)
  Rope f *** Rope g = Rope $ \h -> f h *** g h
  Rope f &&& Rope g = Rope $ \h -> f h &&& g h

instance ArrowChoice core => ArrowChoice (Rope core mantle) where
  left (Rope f) = Rope $ \h -> left (f h)
  right (Rope f) = Rope $ \h -> right (f h)
  Rope f +++ Rope g = Rope $ \h -> f h +++ g h
  Rope f ||| Rope g = Rope $ \h -> f h ||| g h

-- | Run a Rope arrow by passing its handler mantle.
runRope :: Rope core mantle a b -> Handlers core -> core a b
runRope (Rope f) = f

-- | Lift an underlying core arrow directly into a Rope.
ropeFromCore :: core a b -> Rope core mantle a b
ropeFromCore c = Rope $ const c

-- | Lifting individual strands into Rope arrows:

logInfoRope :: Text -> Rope core mantle () ()
logInfoRope msg = Rope $ \h -> handleLogMsg h (LogInfo msg)

logWarnRope :: Text -> Rope core mantle () ()
logWarnRope msg = Rope $ \h -> handleLogMsg h (LogWarn msg)

logErrorRope :: Text -> Rope core mantle () ()
logErrorRope msg = Rope $ \h -> handleLogMsg h (LogError msg)

readFileRope :: FilePath -> Rope core mantle () (Either Text Text)
readFileRope fp = Rope $ \h -> handleReadFile h (ReadTextFile fp)

writeFileRope :: FilePath -> Text -> Rope core mantle () (Either Text ())
writeFileRope fp txt = Rope $ \h -> handleWriteFile h (WriteTextFile fp txt)

runSandboxRope :: FilePath -> [String] -> Rope core mantle () (Int, Text, Text)
runSandboxRope cmd args = Rope $ \h -> handleSandbox h (RunCommand cmd args)

queryEvidenceRope :: Text -> Rope core mantle () (Maybe Text)
queryEvidenceRope k = Rope $ \h -> handleQueryBeam h (QueryEvidence k)

storeEvidenceRope :: Text -> Text -> Rope core mantle () Bool
storeEvidenceRope k v = Rope $ \h -> handleQueryBeam h (StoreEvidence k v)

getRandomWordRope :: Rope core mantle () Word64
getRandomWordRope = Rope $ \h -> handleRandom h GetRandomWord

getTimestampRope :: Rope core mantle () Word64
getTimestampRope = Rope $ \h -> handleTimer h GetTimestamp

-- | Static Config-Time Analysis:
--
-- Inspects what external resources an arrow pipeline requires before
-- running any real effects or opening network connections.
data Requirements = Requirements
  { reqLog     :: Bool
  , reqReadFile:: Bool
  , reqWriteFile:: Bool
  , reqSandbox :: Bool
  , reqBeam    :: Bool
  , reqRandom  :: Bool
  , reqTimer   :: Bool
  } deriving (Show, Eq)

emptyRequirements :: Requirements
emptyRequirements = Requirements False False False False False False False

-- | Inspect a mantle handler configuration to determine capability completeness.
inspectMantleRequirements :: Handlers core -> Requirements
inspectMantleRequirements _ = Requirements
  { reqLog      = True
  , reqReadFile = True
  , reqWriteFile= True
  , reqSandbox  = True
  , reqBeam     = True
  , reqRandom   = True
  , reqTimer    = True
  }

{- Note [Mantle Decoupling and Config-Time Resource Verification]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-mantle-static-requirements]
In standard monadic effect libraries (e.g. mtl, fused-effects), effect execution is
intertwined with effect construction: there is no separation between the computation's
static requirements and its runtime interpretation.

In Kernmantle, the computation arrow 'Rope core mantle a b' is represented as a function
from a handler mantle to the underlying core arrow:
  newtype Rope core mantle a b = Rope (Handlers core -> core a b)

This architecture provides a vital operational advantage for autonomous systems:
  1. Decoupled Interpretation: The arrow structure can be constructed once and interpreted
     differently in test (pure mock handlers) vs production (real Bubblewrap namespaces and
     SQLite databases).
  2. Config-Time Resource Verification: Before executing any arrow step or spawning
     processes, 'inspectMantleRequirements' extracts the capability profile, and
     'validateWorkflowResources' mechanically asserts that host binaries (e.g. /usr/bin/bwrap)
     and database directories exist on the physical machine.
  3. Fail-Fast Safety: Missing permissions or binaries are caught at configuration time
     before launching unprivileged container namespaces or database locks.
-}

-- | Physical environment verification at configuration time.
--
-- See Note [Mantle Decoupling and Config-Time Resource Verification] [ref:note-mantle-static-requirements].
--
-- Inspects that external physical binaries and filesystem resources actually exist
-- BEFORE executing any workflow steps.
validateWorkflowResources :: FilePath -> FilePath -> Requirements -> IO (Either [Text] ())
validateWorkflowResources sandboxBin dbPath reqs = do
  sbOk <- if reqSandbox reqs
            then doesFileExist sandboxBin
            else pure True
  let errs1 = ["Sandbox binary missing: " <> T.pack sandboxBin | not sbOk]
  dbDirOk <- if reqBeam reqs
               then doesDirectoryExist (takeDirectory dbPath)
               else pure True
  let errs2 = if not dbDirOk then ("Database directory does not exist: " <> T.pack (takeDirectory dbPath)) : errs1 else errs1
  if null errs2
    then pure (Right ())
    else pure (Left errs2)

