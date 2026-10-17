{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}

-- | Strand definitions for the Kernmantle effect orchestration layer.
--
-- Strands represent individual effect requests in an arrow pipeline.
-- Each strand is a binary type constructor (a -> b) representing inputs and outputs.
module Effect.Strand
  ( LogMsg(..)
  , ReadFile(..)
  , WriteFile(..)
  , RunSandbox(..)
  , QueryBeam(..)
  , Random(..)
  , Timer(..)
  ) where

import Data.Text (Text)
import Data.Word (Word64)

-- | Logging strand for diagnostic and operational trace messages
data LogMsg a b where
  LogInfo  :: Text -> LogMsg () ()
  LogWarn  :: Text -> LogMsg () ()
  LogError :: Text -> LogMsg () ()

-- | File system read strand
data ReadFile a b where
  ReadTextFile :: FilePath -> ReadFile () (Either Text Text)

-- | File system write strand
data WriteFile a b where
  WriteTextFile :: FilePath -> Text -> WriteFile () (Either Text ())

-- | Sandboxed process execution strand
data RunSandbox a b where
  RunCommand :: FilePath -> [String] -> RunSandbox () (Int, Text, Text)

-- | Beam persistence query strand for evidence and counterexample storage
data QueryBeam a b where
  QueryEvidence :: Text -> QueryBeam () (Maybe Text)
  StoreEvidence :: Text -> Text -> QueryBeam () Bool

-- | Pseudo-random generation strand
data Random a b where
  GetRandomWord :: Random () Word64
  GetRandomRange :: (Int, Int) -> Random () Int

-- | Timer and timestamp strand
data Timer a b where
  GetTimestamp :: Timer () Word64
  DelayMicroseconds :: Int -> Timer () ()
