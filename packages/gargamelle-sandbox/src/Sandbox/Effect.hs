{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}

-- | Milestone M3: Sandboxing Effect Definitions
--
-- Defines first-class resource-bounded sandboxing strands for executing
-- candidate syntheses in isolated environments.
module Sandbox.Effect
  ( ResourceLimits(..)
  , defaultLimits
  , SandboxOp(..)
  ) where

import Data.Text (Text)

-- | Resource limits for isolated sandbox execution
data ResourceLimits = ResourceLimits
  { limitTimeoutSeconds :: Int
  , limitMemoryMB       :: Int
  } deriving (Show, Eq)

-- | Default conservative limits: 30 seconds timeout, 1024 MB memory
defaultLimits :: ResourceLimits
defaultLimits = ResourceLimits
  { limitTimeoutSeconds = 30
  , limitMemoryMB       = 1024
  }

-- | Sandboxed process and isolation operations
data SandboxOp a b where
  -- | Run a command with explicit resource bounds
  RunIsolated :: ResourceLimits -> FilePath -> [String] -> SandboxOp () (Int, Text, Text)
  -- | Acquire an isolated temporary directory for synthesis artifacts
  WithIsolatedDir :: Text -> (FilePath -> IO r) -> SandboxOp () (Either Text r)
