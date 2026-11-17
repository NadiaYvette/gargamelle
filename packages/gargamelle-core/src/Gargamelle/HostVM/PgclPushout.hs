-- VERBATIM_CODE_SEED: TP-008D
-- TARGET_REPO: ~/src/gargamelle
-- TARGET_PACKAGE: gargamelle, organ-bank
-- TARGET_FILES:
--   src/Gargamelle/HostVM/PgclPushout.hs

{-# LANGUAGE BangPatterns, DataKinds, GADTs, KindSignatures, MagicHash, OverloadedStrings #-}
{-# LANGUAGE PolyKinds, RankNTypes, ScopedTypeVariables #-}

module Gargamelle.HostVM.PgclPushout
  ( HostOSKernel(..)
  , PullbackHookInterface(..)
  , HostBaseInstitution(..)
  , PortablePgclWeave(..)
  , SynthesizedKernelShim(..)
  , SeparateObjectABI(..)
  , compileSeparateObjectABI
  , defaultPgclHookInterface
  , hostBaseForKernel
  , pgclHostVMPushout
  , sweepAllTargetKernels
  ) where

import Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IM
import Data.Primitive.PrimArray (PrimArray, primArrayFromList, sizeofPrimArray, indexPrimArray)
import Data.Primitive.SmallArray (smallArrayFromList)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Exts (unsafeCoerce#)

import Polytropos (RecordF)
import Polytropos.Core (Pair(..), Rep(..), RowRep(..))
import Polytropos.RowMorph (RowMorph(..))
import Penelope.Core.Syntax (Penelope(..))
import Penelope.Perceus (RTSProfile(..), SizeClass(..))
import Penelope.Backend.Plugin
  ( TargetLayout(..)
  , BackendPlugin
  , defaultHostTargetLayout
  , compileWithBackend
  )
import Penelope.Stage.OrganIR
  ( StagedKernelError
  , stageFreestandingModule
  )
import Penelope.Backend.MLIR (SSAVal(..), mlirBackendPlugin)
import Penelope.Backend.Gimple (GimpleVal(..), gimpleBackendPlugin)

-- | Separate Compilation Module Artifact with evidence vector C-ABI.
data SeparateObjectABI artifact = SeparateObjectABI
  { soaModuleName       :: !Text
  , soaRTSProfile       :: !RTSProfile
  , soaEvidenceSlots    :: ![Int]
  , soaCHeader          :: !Text
  , soaCompiledArtifact :: !artifact
  } deriving (Show, Eq)

-- | Compiles a standalone module into a separate compilation ABI artifact.
compileSeparateObjectABI
  :: Text
  -> TargetLayout
  -> RTSProfile
  -> RowMorph ef_local ef_ambient
  -> BackendPlugin val carrier artifact
  -> RecordF val ins
  -> Penelope '[] ef_local ins outs
  -> SeparateObjectABI artifact
compileSeparateObjectABI !modName !layout !rts (RowMorph !permArr) !backend !initFrame !prog =
  let !nSlots    = sizeofPrimArray permArr
      !slots     = [ indexPrimArray permArr i | i <- [0 .. nSlots - 1] ]
      !artifact  = compileWithBackend backend layout rts prog initFrame
      !cHeader   = T.unlines
        [ "/* Auto-generated Frankenstein 2.0 Separate Compilation ABI Header */"
        , "/* Module: " <> modName <> " | RTS Profile: " <> T.pack (show rts) <> " */"
        , "static inline void __organ_slice_ev_" <> modName
          <> "(struct PenelopeEffVec* dst, const struct PenelopeEffVec* ambient) {"
        , T.unlines
            [ "  dst->handlers[" <> T.pack (show i) <> "] = ambient->handlers[" <> T.pack (show s) <> "];"
            | (i, s) <- zip [0 :: Int ..] slots
            ]
        , "}"
        ]
  in SeparateObjectABI
       { soaModuleName       = modName
       , soaRTSProfile       = rts
       , soaEvidenceSlots    = slots
       , soaCHeader          = cHeader
       , soaCompiledArtifact = artifact
       }

-- | Target open-source operating system kernels for the Sectile `pgcl` sweep.
data HostOSKernel
  = KernelLinux
    -- ^ Linux (`mm/pgcl_core.c`): `struct folio`, `page_vma_mapped_walk` (PVMW), RCU / seqcount views.
  | KernelFreeBSD
    -- ^ FreeBSD (`vm/vm_pgcl_core.c`): `struct vm_page`, `struct vm_radix`, `vm_page_lock`.
  | KernelIllumos
    -- ^ illumos (`uts/common/vm/hat_pgcl.c`): `page_t`, `hat_t`, `kmutex_t` / `p_selock`.
  | KernelSeL4
    -- ^ seL4 (`src/arch/pgcl_cap.c`): `cap_t`, `cte_t`, capability derivation tree under `#![freestanding_linear]`.
  | KernelZircon
    -- ^ Zircon (`kernel/vm/pgcl_vmo.cc`): `vm_page_t`, `VmObjectPaged`, `VmCowPages` spinlocks.
  deriving (Show, Eq, Ord, Enum, Bounded)

-- | Minimal Pullback Hook Interface $C$ shared across all kernel VM subsystems:
--   Maps canonical `pgclOpenClusterRow` fields (slot 0: `pfn_base`, slot 1: `cluster_order`,
--   slot 2: `populated_mask`) onto the host kernel's native VM structs.
data PullbackHookInterface = PullbackHookInterface
  { phiClusterRowFields :: ![Text]
    -- ^ Canonical `Polytropos` row labels: `["cluster_order", "pfn_base", "populated_mask"]`
  , phiHookPoints       :: ![Text]
    -- ^ Intercepted VM lifecycle hooks: `["on_pte_fault_batch", "on_folio_split", "on_tlb_shootdown"]`
  , phiClusterSizeClass :: !SizeClass
  } deriving (Show, Eq)

defaultPgclHookInterface :: PullbackHookInterface
defaultPgclHookInterface = PullbackHookInterface
  { phiClusterRowFields = ["cluster_order", "pfn_base", "populated_mask"]
  , phiHookPoints       = ["on_pte_fault_batch", "on_folio_split", "on_tlb_shootdown"]
  , phiClusterSizeClass = SizeClass 3
  }

-- | Host Base Institution $B_{\text{host}}$ extracted via `hs-tree-sitter` from the
--   target OS kernel's VM headers (`mm/rmap.c`, `vm/vm_page.c`, etc.).
data HostBaseInstitution = HostBaseInstitution
  { hbiKernel         :: !HostOSKernel
  , hbiTargetSubpath  :: !Text
  , hbiPageStruct     :: !Text
  , hbiWalkStruct     :: !Text
  , hbiSyncPrimitive  :: !Text
  , hbiTargetLayout   :: !TargetLayout
  } deriving (Show, Eq)

-- | Portable `pgcl` Weave Institution $W_{\text{pgcl}}$:
--   Expressed once as a verified `#[freestanding_linear]` (`RTSFreestandingLinear`)
--   `Penelope` hypergraph over `pgclOpenClusterRow`.
data PortablePgclWeave ef ins outs = PortablePgclWeave
  { ppwName       :: !Text
  , ppwBoxedSlots :: !(IntMap SizeClass)
  , ppwHypergraph :: !(Penelope '[] ef ins outs)
  }

-- | Output of the Categorical Pushout $B_{\text{host}} \sqcup_C W_{\text{pgcl}}$:
--   Contains the synthesized 100-line Profunctor Adapter Funnel C header,
--   the GCC `-fgimple` SSA module (with `PlaceInPlaceLinear` `COMPONENT_REF` stores and `.MEM` `VDEF`s),
--   and the MLIR / freestanding LLVM artifact for `no_std` / Zircon / Telix integration.
data SynthesizedKernelShim = SynthesizedKernelShim
  { sksKernel             :: !HostOSKernel
  , sksTargetFile         :: !Text
  , sksProfunctorFunnelH  :: !Text
  , sksGimpleSSAModule    :: !Text
  , sksMLIRFreestanding   :: !Text
  } deriving (Show, Eq)

-- | Returns the `HostBaseInstitution` $B_{\text{host}}$ for each target kernel.
hostBaseForKernel :: HostOSKernel -> HostBaseInstitution
hostBaseForKernel KernelLinux = HostBaseInstitution
  { hbiKernel        = KernelLinux
  , hbiTargetSubpath = "mm/pgcl_core.c"
  , hbiPageStruct    = "struct folio"
  , hbiWalkStruct    = "struct page_vma_mapped_walk"
  , hbiSyncPrimitive = "rcu_read_lock() / folio_trylock()"
  , hbiTargetLayout  = defaultHostTargetLayout
  }
hostBaseForKernel KernelFreeBSD = HostBaseInstitution
  { hbiKernel        = KernelFreeBSD
  , hbiTargetSubpath = "vm/vm_pgcl_core.c"
  , hbiPageStruct    = "struct vm_page"
  , hbiWalkStruct    = "struct vm_radix"
  , hbiSyncPrimitive = "vm_page_lock(m) / vm_radix_lookup()"
  , hbiTargetLayout  = defaultHostTargetLayout
  }
hostBaseForKernel KernelIllumos = HostBaseInstitution
  { hbiKernel        = KernelIllumos
  , hbiTargetSubpath = "uts/common/vm/hat_pgcl.c"
  , hbiPageStruct    = "page_t"
  , hbiWalkStruct    = "hat_t"
  , hbiSyncPrimitive = "page_tryupgrade(pp) / hat_enter()"
  , hbiTargetLayout  = defaultHostTargetLayout
  }
hostBaseForKernel KernelSeL4 = HostBaseInstitution
  { hbiKernel        = KernelSeL4
  , hbiTargetSubpath = "src/arch/pgcl_cap.c"
  , hbiPageStruct    = "cap_t"
  , hbiWalkStruct    = "cte_t"
  , hbiSyncPrimitive = "cap_frame_cap_get_capFSize() [Linear Capability Proof]"
  , hbiTargetLayout  = defaultHostTargetLayout
  }
hostBaseForKernel KernelZircon = HostBaseInstitution
  { hbiKernel        = KernelZircon
  , hbiTargetSubpath = "kernel/vm/pgcl_vmo.cc"
  , hbiPageStruct    = "vm_page_t"
  , hbiWalkStruct    = "VmCowPages"
  , hbiSyncPrimitive = "Guard<CriticalMutex> / VmObjectPaged::CommitRange()"
  , hbiTargetLayout  = defaultHostTargetLayout
  }

-- | Computes the Categorical Pushout $B_{\text{host}} \sqcup_C W_{\text{pgcl}}$:
--   1. Verifies that $W_{\text{pgcl}}$ satisfies `RTSFreestandingLinear` (zero RC headers,
--      zero heap closures, 100% static in-place slot writes).
--   2. Synthesizes the host-specific Profunctor Adapter Funnel mapping `hbiPageStruct`
--      and `hbiWalkStruct` to `PolytroposRep` slots `[0..2]`.
--   3. Lowers $W_{\text{pgcl}}$ through `gimpleBackendPlugin` (`-fgimple` SSA) and
--      `mlirBackendPlugin` (`organ`/`scf`/`llvm`).
pgclHostVMPushout
  :: PullbackHookInterface
  -> HostBaseInstitution
  -> PortablePgclWeave ef ins outs
  -> Either StagedKernelError SynthesizedKernelShim
pgclHostVMPushout !hookC !hostB (PortablePgclWeave !wName !boxedIn !hypergraph) = do
  let !layout      = hbiTargetLayout hostB
      !gimpleFrame = RowRep (Rep 0 (smallArrayFromList [unsafeCoerce# (GimpleVal "cluster_rep_3(D)")]))
      !mlirFrame   = RowRep (Rep 0 (smallArrayFromList [unsafeCoerce# (SSAVal "%cluster_rep_0")]))
      !idPerm      = RowMorph (primArrayFromList [0, 1, 2])

  -- Stage 1: Lower via `gimpleBackendPlugin` under `RTSFreestandingLinear`
  !gimpleCode <-
    stageFreestandingModule
      (wName <> "_gimple")
      layout
      boxedIn
      gimpleBackendPlugin
      gimpleFrame
      hypergraph

  -- Stage 2: Lower via `mlirBackendPlugin` + Separate Compilation ABI header
  !mlirCode <-
    stageFreestandingModule
      (wName <> "_mlir")
      layout
      boxedIn
      mlirBackendPlugin
      mlirFrame
      hypergraph

  let !sepABI      = compileSeparateObjectABI
                       wName layout RTSFreestandingLinear idPerm
                       gimpleBackendPlugin gimpleFrame hypergraph
      !funnelShim  = renderProfunctorFunnelHeader hookC hostB (soaCHeader sepABI)

  Right SynthesizedKernelShim
    { sksKernel            = hbiKernel hostB
    , sksTargetFile        = hbiTargetSubpath hostB
    , sksProfunctorFunnelH = funnelShim
    , sksGimpleSSAModule   = gimpleCode
    , sksMLIRFreestanding  = mlirCode
    }

-- | Synthesizes the Profunctor Adapter Funnel bridging the host OS kernel's native
--   page/walk structs to the canonical 3-slot `#[freestanding_linear]` `PolytroposRep`.
renderProfunctorFunnelHeader
  :: PullbackHookInterface
  -> HostBaseInstitution
  -> Text
  -> Text
renderProfunctorFunnelHeader !hookC !hostB !abiHeader =
  T.unlines
    [ "/* ========================================================================= */"
    , "/* Synthesized HostVM Pushout Shim (B_host (+) _C W_pgcl)                    */"
    , "/* Target Kernel : " <> T.pack (show (hbiKernel hostB))
    , "/* Target File   : " <> hbiTargetSubpath hostB
    , "/* Page Struct   : " <> hbiPageStruct hostB
    , "/* Walk Struct   : " <> hbiWalkStruct hostB
    , "/* Sync Protocol : " <> hbiSyncPrimitive hostB
    , "/* Memory Profile: #[freestanding_linear] (Zero RC Header, In-Place VDEF)    */"
    , "/* ========================================================================= */"
    , ""
    , "struct PolytroposRep {"
    , "  unsigned long slots[3]; /* [0]=cluster_order, [1]=pfn_base, [2]=populated_mask */"
    , "};"
    , ""
    , abiHeader
    , "/* Contravariant Ingress Profunctor: Project " <> hbiPageStruct hostB <> " -> PolytroposRep */"
    , "static inline void __pgcl_ingress_project(struct PolytroposRep* dst, const void* host_page_ptr) {"
    , "  /* Mapped via PullbackHookInterface C: " <> T.intercalate ", " (phiClusterRowFields hookC) <> " */"
    , "  const unsigned long* raw = (const unsigned long*)host_page_ptr;"
    , "  dst->slots[0] = raw[0]; /* cluster_order */"
    , "  dst->slots[1] = raw[1]; /* pfn_base      */"
    , "  dst->slots[2] = raw[2]; /* populated_mask */"
    , "}"
    , ""
    , "/* Covariant Egress Profunctor: Scatter in-place PolytroposRep -> " <> hbiWalkStruct hostB <> " */"
    , "static inline void __pgcl_egress_scatter(void* host_walk_ptr, const struct PolytroposRep* src) {"
    , "  unsigned long* raw = (unsigned long*)host_walk_ptr;"
    , "  raw[0] = src->slots[0];"
    , "  raw[1] = src->slots[1];"
    , "  raw[2] = src->slots[2];"
    , "}"
    ]

-- | Sweeps the single verified `pgcl` weave across all 5 target kernels in one pass.
sweepAllTargetKernels
  :: Either StagedKernelError [SynthesizedKernelShim]
sweepAllTargetKernels =
  let !idMorph = unsafeCoerce# (RowMorph (primArrayFromList [0] :: PrimArray Int))
      !weave   = PortablePgclWeave
        { ppwName       = "pgcl_bjd_nidc_core"
        , ppwBoxedSlots = IM.singleton 0 (SizeClass 3)
        , ppwHypergraph = Route idMorph
        }
      !kernels = [KernelLinux, KernelFreeBSD, KernelIllumos, KernelSeL4, KernelZircon]
  in traverse (\k -> pgclHostVMPushout defaultPgclHookInterface (hostBaseForKernel k) weave) kernels