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
import System.Process (CreateProcess(..), proc, readCreateProcessWithExitCode, readProcessWithExitCode)
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
  - Network Namespace & Loopback Isolation Defense ('--unshare-all --share-net'):
    On modern Linux distributions (e.g. Ubuntu 24.04 with kernel AppArmor restrictions on
    unprivileged user namespaces), netlink address assignment ('RTM_NEWADDR') to configure 'lo'
    in private network namespaces is blocked with EPERM ("bwrap: loopback: Failed RTM_NEWADDR").
    When container setup errors occur ("bwrap:" prefix on stderr), execution transparently
    retries with '--share-net'. This retains host network loopback whilst preserving full filesystem,
    PID, IPC, and mount namespace isolation.
  - Graceful Fallback: When '/usr/bin/bwrap' is absent or restricted by host kernel policy,
    'executeSandboxed' gracefully falls back to process execution with timeout and exception bracketing.
-}

-- | Detect whether an exit failure was caused by Bubblewrap container setup itself
-- (e.g. AppArmor unprivileged user namespace or netlink restriction: "bwrap: loopback: Failed RTM_NEWADDR")
-- rather than the candidate process failing inside the sandbox.
isBwrapSetupError :: String -> Bool
isBwrapSetupError errStr = "bwrap:" `T.isInfixOf` T.pack errStr

-- | Production execution of sandboxed commands.
-- Automatically leverages Bubblewrap (/usr/bin/bwrap) and /usr/bin/timeout when present,
-- enforcing physical namespace isolation and resource constraints with transparent
-- '--share-net' fallback when host AppArmor limits unprivileged network namespaces.
--
-- See Note [Bubblewrap Namespace Isolation and Resource Limiting Boundaries] [ref:note-sandbox-bwrap-isolation].
executeSandboxed :: ResourceLimits -> FilePath -> [String] -> IO (Int, Text, Text)
executeSandboxed limits cmd args = do
  hasBwrap <- doesFileExist "/usr/bin/bwrap"
  hasTimeout <- doesFileExist "/usr/bin/timeout"
  let timeoutSecs = show (max 1 (limitTimeoutSeconds limits))
  let runDirect = do
        let (runnerCmd, runnerArgs) =
              if hasTimeout
                then ("/usr/bin/timeout", timeoutSecs : cmd : args)
                else (cmd, args)
        res <- try (readProcessWithExitCode runnerCmd runnerArgs "")
        case res of
          Right (ExitSuccess, stdoutStr, stderrStr) ->
            pure (0, T.pack stdoutStr, T.pack stderrStr)
          Right (ExitFailure code, stdoutStr, stderrStr) ->
            pure (code, T.pack stdoutStr, T.pack stderrStr)
          Left (err :: SomeException) ->
            pure (-1, T.empty, T.pack (show err))

  if not hasBwrap
    then runDirect
    else do
      let runBwrap extraFlags = do
            let bwrapArgs =
                  [ "--ro-bind", "/", "/"
                  , "--dev", "/dev"
                  , "--proc", "/proc"
                  , "--tmpfs", "/tmp"
                  ] ++ extraFlags ++
                  [ "--die-with-parent"
                  , "--"
                  , cmd
                  ] ++ args
            let (runnerCmd, runnerArgs) =
                  if hasTimeout
                    then ("/usr/bin/timeout", timeoutSecs : "/usr/bin/bwrap" : bwrapArgs)
                    else ("/usr/bin/bwrap", bwrapArgs)
            (try (readProcessWithExitCode runnerCmd runnerArgs "") :: IO (Either SomeException (ExitCode, String, String)))

      resStrict <- runBwrap ["--unshare-all"]
      case resStrict of
        Right (ExitSuccess, stdoutStr, stderrStr) ->
          pure (0, T.pack stdoutStr, T.pack stderrStr)
        Right (ExitFailure code, stdoutStr, stderrStr)
          | isBwrapSetupError stderrStr -> do
              -- Fallback: retry with --share-net to avoid RTM_NEWADDR EPERM under AppArmor
              resShareNet <- runBwrap ["--unshare-all", "--share-net"]
              case resShareNet of
                Right (ExitSuccess, o, e) ->
                  pure (0, T.pack o, T.pack e)
                Right (ExitFailure c, o, e)
                  | isBwrapSetupError e -> runDirect
                  | otherwise -> pure (c, T.pack o, T.pack e)
                Left _ -> runDirect
          | otherwise ->
              pure (code, T.pack stdoutStr, T.pack stderrStr)
        Left _ -> runDirect

-- | Explicit execution inside an isolated working directory with Bubblewrap writable bind.
-- Automatically handles AppArmor network namespace restrictions via '--share-net'
-- and falls back to timeout-bounded execution if Bubblewrap is unusable on host.
--
-- See Note [Bubblewrap Namespace Isolation and Resource Limiting Boundaries] [ref:note-sandbox-bwrap-isolation].
executeBubblewrapSandboxed :: ResourceLimits -> FilePath -> FilePath -> [String] -> IO (Int, Text, Text)
executeBubblewrapSandboxed limits workDir cmd args = do
  hasBwrap <- doesFileExist "/usr/bin/bwrap"
  hasTimeout <- doesFileExist "/usr/bin/timeout"
  let timeoutSecs = show (max 1 (limitTimeoutSeconds limits))
  let runDirect = do
        let (runnerCmd, runnerArgs) =
              if hasTimeout
                then ("/usr/bin/timeout", timeoutSecs : cmd : args)
                else (cmd, args)
        let cp = (proc runnerCmd runnerArgs) { cwd = Just workDir }
        res <- try (readCreateProcessWithExitCode cp "")
        case res of
          Right (ExitSuccess, stdoutStr, stderrStr) ->
            pure (0, T.pack stdoutStr, T.pack stderrStr)
          Right (ExitFailure code, stdoutStr, stderrStr) ->
            pure (code, T.pack stdoutStr, T.pack stderrStr)
          Left (err :: SomeException) ->
            pure (-1, T.empty, T.pack (show err))

  if not hasBwrap
    then runDirect
    else do
      let runBwrap extraFlags = do
            let bwrapArgs =
                  [ "--ro-bind", "/", "/"
                  , "--dev", "/dev"
                  , "--proc", "/proc"
                  , "--tmpfs", "/tmp"
                  , "--bind", workDir, workDir
                  , "--chdir", workDir
                  ] ++ extraFlags ++
                  [ "--die-with-parent"
                  , "--"
                  , cmd
                  ] ++ args
            let (runnerCmd, runnerArgs) =
                  if hasTimeout
                    then ("/usr/bin/timeout", timeoutSecs : "/usr/bin/bwrap" : bwrapArgs)
                    else ("/usr/bin/bwrap", bwrapArgs)
            (try (readProcessWithExitCode runnerCmd runnerArgs "") :: IO (Either SomeException (ExitCode, String, String)))

      resStrict <- runBwrap ["--unshare-all"]
      case resStrict of
        Right (ExitSuccess, stdoutStr, stderrStr) ->
          pure (0, T.pack stdoutStr, T.pack stderrStr)
        Right (ExitFailure code, stdoutStr, stderrStr)
          | isBwrapSetupError stderrStr -> do
              -- Fallback: retry with --share-net to avoid RTM_NEWADDR EPERM under AppArmor
              resShareNet <- runBwrap ["--unshare-all", "--share-net"]
              case resShareNet of
                Right (ExitSuccess, o, e) ->
                  pure (0, T.pack o, T.pack e)
                Right (ExitFailure c, o, e)
                  | isBwrapSetupError e -> runDirect
                  | otherwise -> pure (c, T.pack o, T.pack e)
                Left _ -> runDirect
          | otherwise ->
              pure (code, T.pack stdoutStr, T.pack stderrStr)
        Left _ -> runDirect

-- | Bracketed temporary directory allocation guaranteeing cleanup.
--
-- Safely creates an isolated staging directory under @/tmp/gargamelle-sandbox-<prefix>@,
-- executes the provided callback, and guarantees recursive cleanup even if exceptions occur.
--
-- Parameters:
--   - 'Text': Prefix slug for the directory name.
--   - @(FilePath -> IO r)@: Action to execute with the ephemeral directory path.
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

-- | Deterministic pure mock for sandboxed runs in unit tests and mock interpreters.
--
-- Returns exit code 0, a synthetic stdout payload indicating the executed command
-- and argument count, and empty stderr without invoking OS processes or filesystem calls.
pureMockSandboxRun :: ResourceLimits -> FilePath -> [String] -> (Int, Text, Text)
pureMockSandboxRun _limits cmd args =
  (0, T.pack ("mock-output-for-" ++ cmd ++ "-with-" ++ show (length args) ++ "-args"), T.empty)
