-- VERBATIM_CODE_SEED: TP-007F
-- TARGET_REPO: ~/src/gargamelle
-- TARGET_PACKAGE: gargamelle-sheaf, frankenstein
-- TARGET_FILES:
--   src/Gargamelle/Sheaf/FFI.hs

{-# LANGUAGE BangPatterns, DataKinds, GADTs, KindSignatures, OverloadedStrings, PolyKinds #-}

module Gargamelle.Sheaf.FFI
  ( ModuleStalkSpec(..)
  , FFIObstruction(..)
  , FFIBoundaryAdapter(..)
  , verifyFFISheafEdge
  , synthesizeFFIBoundaryAdapter
  ) where

import Data.Text (Text)
import Penelope.Perceus (RTSProfile(..))

-- | Semantic Stalk $\mathcal{F}(u)$ at module vertex `u` in the polyglot call graph.
data ModuleStalkSpec = ModuleStalkSpec
  { mssModuleName       :: !Text
  , mssLanguage         :: !Text
  , mssRTSProfile       :: !RTSProfile
  , mssHasMultiShot     :: !Bool
    -- ^ True if module `u` holds active multi-shot continuations (e.g. Mercury/Prolog `NonDet`).
  , mssMutatesInPlace   :: !Bool
    -- ^ True if module `u` performs linear in-place pointer mutation (e.g. Rust `&mut` / C99).
  , mssSpawnsThreads    :: !Bool
    -- ^ True if module `u` transfers values across OS threads or `io_uring` rings.
  , mssProducesLazyList :: !Bool
    -- ^ True if module `u` returns potentially unevaluated lazy `[Char]` thunks.
  } deriving (Show, Eq)

-- | Non-vanishing $H^1$ cocycle obstructions detected along a cross-language FFI edge $e = (u \to v)$.
data FFIObstruction
  = ObstructionNonDetCrossesLinear !Text !Text
    -- ^ Caller `u` holds a backtracking choice point while callee `v` mutates a linear pointer in-place!
  | ObstructionThreadLocalCrossesShared !Text !Text
    -- ^ Caller `u` uses non-atomic `RTSLean4ThreadLocal` (`m_rc > 0`) while callee `v` shares across threads!
  | ObstructionUnboundedLazyInKernel !Text !Text
    -- ^ Caller `u` passes lazy thunks into a `#[freestanding_linear]` kernel module `v`!
  deriving (Show, Eq)

-- | Automatically synthesized boundary handler (`OpH` / Profunctor Funnel wrapper)
--   that resolves an `FFIObstruction` so the sheaf gluing condition $(\delta^0 x)_e = \top$ holds.
data FFIBoundaryAdapter
  = AdapterIdentityZeroCopy
    -- ^ Stalks are directly compatible: 0-instruction pointer pass!
  | AdapterCloneOnBacktrack !Text
    -- ^ Wraps the linear pointer in a Perceus CoW snapshot handler before entering `NonDet` scope.
  | AdapterLeanMarkMT !Text
    -- ^ Emits `lean_mark_mt(obj)` at the FFI boundary to transition `m_rc > 0` to atomic `m_rc < 0`.
  | AdapterForceContiguousUTF8 !Text
    -- ^ Forces and compacts any `RopeThunk` / `RopeCat` spine into a single contiguous `UTF8Slice`.
  | AdapterCompose ![FFIBoundaryAdapter]
  deriving (Show, Eq)

-- | Checks the sheaf restriction map along cross-language call edge $e = (u \to v)$.
--   Returns `Right ()` if $(\delta^0 x)_e = \top$, or `Left [FFIObstruction]` if an $H^1$ cocycle exists.
verifyFFISheafEdge
  :: ModuleStalkSpec  -- ^ Caller stalk $\mathcal{F}(u)$
  -> ModuleStalkSpec  -- ^ Callee stalk $\mathcal{F}(v)$
  -> Either [FFIObstruction] ()
verifyFFISheafEdge !caller !callee =
  let !obs1 =
        [ ObstructionNonDetCrossesLinear (mssModuleName caller) (mssModuleName callee)
        | (mssHasMultiShot caller && mssMutatesInPlace callee)
          || (mssMutatesInPlace caller && mssHasMultiShot callee)
        ]
      !obs2 =
        [ ObstructionThreadLocalCrossesShared (mssModuleName caller) (mssModuleName callee)
        | mssRTSProfile caller == RTSLean4ThreadLocal
          && (mssRTSProfile callee == RTSLean4Concurrent || mssSpawnsThreads callee)
        ]
      !obs3 =
        [ ObstructionUnboundedLazyInKernel (mssModuleName caller) (mssModuleName callee)
        | mssProducesLazyList caller && mssRTSProfile callee == RTSFreestandingLinear
        ]
      !allObs = obs1 ++ obs2 ++ obs3
  in case allObs of
       [] -> Right ()
       os -> Left os

-- | Synthesizes the minimal Profunctor / `Penelope` boundary adapter that annihilates
--   all $H^1$ cocycle obstructions on edge $e = (u \to v)$.
synthesizeFFIBoundaryAdapter
  :: ModuleStalkSpec
  -> ModuleStalkSpec
  -> FFIBoundaryAdapter
synthesizeFFIBoundaryAdapter !caller !callee =
  case verifyFFISheafEdge caller callee of
    Right ()  -> AdapterIdentityZeroCopy
    Left !obs ->
      case map resolveSingleObstruction obs of
        [single] -> single
        many     -> AdapterCompose many
  where
    resolveSingleObstruction (ObstructionNonDetCrossesLinear u v) =
      AdapterCloneOnBacktrack ("__organ_ffi_clone_on_backtrack_" <> u <> "_to_" <> v)
    resolveSingleObstruction (ObstructionThreadLocalCrossesShared u v) =
      AdapterLeanMarkMT ("__organ_ffi_lean_mark_mt_" <> u <> "_to_" <> v)
    resolveSingleObstruction (ObstructionUnboundedLazyInKernel u v) =
      AdapterForceContiguousUTF8 ("__organ_ffi_force_contiguous_utf8_" <> u <> "_to_" <> v)
