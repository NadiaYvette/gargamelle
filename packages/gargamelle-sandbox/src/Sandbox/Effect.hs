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

-- | Resource limits for isolated sandbox execution.
--
-- Restricts maximum wall-clock execution time and RAM footprint for candidate synthesis runs.
data ResourceLimits = ResourceLimits
  { limitTimeoutSeconds :: Int
    -- ^ Maximum wall-clock seconds before child processes are terminated by @/usr/bin/timeout@.
  , limitMemoryMB       :: Int
    -- ^ Maximum RAM memory budget in megabytes allocated to the sandboxed container.
  } deriving (Show, Eq)

-- | Default conservative limits: 30 seconds timeout, 1024 MB memory.
defaultLimits :: ResourceLimits
defaultLimits = ResourceLimits
  { limitTimeoutSeconds = 30
  , limitMemoryMB       = 1024
  }

-- | Sandboxed process and filesystem isolation operations.
--
-- Expressed as a GADT suitable for Kernmantle Arrow Rope strand embedding.
data SandboxOp a b where
  -- | Run an external command within Bubblewrap container isolation and timeout enforcement,
  -- returning @(exitCode, stdout, stderr)@.
  RunIsolated :: ResourceLimits -> FilePath -> [String] -> SandboxOp () (Int, Text, Text)
  -- | Acquire an ephemeral, isolated temporary directory with guaranteed cleanup upon completion.
  WithIsolatedDir :: Text -> (FilePath -> IO r) -> SandboxOp () (Either Text r)
