{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Milestone M3: Sandbox Handlers
--
-- Provides production IO execution with Bubblewrap container isolation,
-- temporary directory bracketing, and pure mock interpreters for hermetic testing.
module Sandbox.Handler
  ( executeSandboxed
  , executeBubblewrapSandboxed
  , withTempSandboxDir
  , pureMockSandboxRun
  ) where

import Control.Exception (bracket, try, SomeException)
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (createDirectoryIfMissing, doesFileExist, removeDirectoryRecursive)
import System.Exit (ExitCode(..))
import System.FilePath ((</>))
import System.Process (readProcessWithExitCode)
import Sandbox.Effect

{- Note [Bubblewrap Namespace Isolation and Resource Limiting Boundaries]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-sandbox-bwrap-isolation]
In autonomous program synthesis, counterexample-guided inductive synthesis (CEGIS),
and multi-agent refactoring loops, executing untrusted candidate code directly on the host
developer or build machine introduces severe security and operational hazards:
  1. Filesystem Contamination: Errant synthesis candidates or destructive shell commands
     can delete or overwrite repository files, build caches, or system directories.
  2. Ambient Process Interference: Runaway subprocesses or fork bombs can consume all host
     process slots, exhaust file descriptors, or corrupt running compilation servers.
  3. Indefinite Hangs: Unbounded recursive loops or infinite loops in synthesized candidates
     stall the entire synthesis and verification pipeline.

Bubblewrap Container Boundaries & Defense-in-Depth:
Gargamelle resolves these hazards by enforcing unprivileged Linux container isolation:
  - Unprivileged Namespaces ('--unshare-all'): Creates private mount, UTS, IPC, PID, and
    network namespaces without requiring root privileges or setuid binaries.
  - Read-Only Root Filesystem ('--ro-bind / /'): Mounts the host operating system strictly
    read-only, preventing any accidental mutation of host libraries or toolchains.
  - Hermetic System Mounts ('--dev /dev --proc /proc --tmpfs /tmp'): Spawns fresh, isolated
    pseudo-filesystems so candidate processes cannot inspect or signal host processes.
  - Ephemeral Scoped Directory ('--bind workDir workDir --chdir workDir'): Restricts writable
    disk access exclusively to an isolated temporary directory managed via 'withTempSandboxDir'.
  - Lifetime & Resource Enforcement ('--die-with-parent', '/usr/bin/timeout'): Guarantees
    child processes terminate immediately if the parent Haskell runtime dies or exceeds the
    configured 'limitTimeoutSeconds'.
  - Graceful Fallback: When '/usr/bin/bwrap' is absent, 'executeSandboxed' gracefully falls
    back to process execution with timeout and exception bracketing.
-}

-- | Production execution of sandboxed commands.
-- Automatically leverages Bubblewrap (/usr/bin/bwrap) and /usr/bin/timeout when present,
-- enforcing physical namespace isolation and resource constraints.
--
-- See Note [Bubblewrap Namespace Isolation and Resource Limiting Boundaries] [ref:note-sandbox-bwrap-isolation].
executeSandboxed :: ResourceLimits -> FilePath -> [String] -> IO (Int, Text, Text)
executeSandboxed limits cmd args = do
  hasBwrap <- doesFileExist "/usr/bin/bwrap"
  hasTimeout <- doesFileExist "/usr/bin/timeout"
  let timeoutSecs = show (max 1 (limitTimeoutSeconds limits))
  let (runnerCmd, runnerArgs) =
        case (hasTimeout, hasBwrap) of
          (True, True) ->
            ( "/usr/bin/timeout"
            , [timeoutSecs, "/usr/bin/bwrap", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc", "--tmpfs", "/tmp", "--unshare-all", "--die-with-parent", "--", cmd] ++ args
            )
          (True, False) ->
            ( "/usr/bin/timeout"
            , [timeoutSecs, cmd] ++ args
            )
          _ ->
            (cmd, args)
  res <- try (readProcessWithExitCode runnerCmd runnerArgs "")
  case res of
    Right (ExitSuccess, stdoutStr, stderrStr) ->
      pure (0, T.pack stdoutStr, T.pack stderrStr)
    Right (ExitFailure code, stdoutStr, stderrStr) ->
      pure (code, T.pack stdoutStr, T.pack stderrStr)
    Left (err :: SomeException) ->
      pure (-1, T.empty, T.pack (show err))

-- | Explicit execution inside an isolated working directory with Bubblewrap writable bind.
--
-- See Note [Bubblewrap Namespace Isolation and Resource Limiting Boundaries] [ref:note-sandbox-bwrap-isolation].
executeBubblewrapSandboxed :: ResourceLimits -> FilePath -> FilePath -> [String] -> IO (Int, Text, Text)
executeBubblewrapSandboxed limits workDir cmd args = do
  hasBwrap <- doesFileExist "/usr/bin/bwrap"
  hasTimeout <- doesFileExist "/usr/bin/timeout"
  let timeoutSecs = show (max 1 (limitTimeoutSeconds limits))
  let bwrapArgs =
        [ "--ro-bind", "/", "/"
        , "--dev", "/dev"
        , "--proc", "/proc"
        , "--tmpfs", "/tmp"
        , "--bind", workDir, workDir
        , "--chdir", workDir
        , "--unshare-all"
        , "--die-with-parent"
        , "--"
        , cmd
        ] ++ args
  let (runnerCmd, runnerArgs) =
        case (hasTimeout, hasBwrap) of
          (True, True) -> ("/usr/bin/timeout", timeoutSecs : "/usr/bin/bwrap" : bwrapArgs)
          (False, True) -> ("/usr/bin/bwrap", bwrapArgs)
          (True, False) -> ("/usr/bin/timeout", timeoutSecs : cmd : args)
          _ -> (cmd, args)
  res <- try (readProcessWithExitCode runnerCmd runnerArgs "")
  case res of
    Right (ExitSuccess, stdoutStr, stderrStr) ->
      pure (0, T.pack stdoutStr, T.pack stderrStr)
    Right (ExitFailure code, stdoutStr, stderrStr) ->
      pure (code, T.pack stdoutStr, T.pack stderrStr)
    Left (err :: SomeException) ->
      pure (-1, T.empty, T.pack (show err))

-- | Bracketed temporary directory allocation guaranteeing cleanup
withTempSandboxDir :: Text -> (FilePath -> IO r) -> IO (Either Text r)
withTempSandboxDir prefix action = do
  let baseDir = "/tmp" </> ("gargamelle-sandbox-" ++ T.unpack prefix)
  bracket
    (createDirectoryIfMissing True baseDir >> pure baseDir)
    (\dir -> try (removeDirectoryRecursive dir) :: IO (Either SomeException ()))
    (\dir -> do
        res <- try (action dir)
        case res of
          Right val -> pure (Right val)
          Left (err :: SomeException) -> pure (Left (T.pack (show err))))

-- | Deterministic pure mock for sandboxed runs in unit tests
pureMockSandboxRun :: ResourceLimits -> FilePath -> [String] -> (Int, Text, Text)
pureMockSandboxRun _limits cmd args =
  (0, T.pack ("mock-output-for-" ++ cmd ++ "-with-" ++ show (length args) ++ "-args"), T.empty)
