# PACKAGES.md — Gargamelle Multi-Package Suite Register

**Status:** LIVING REGISTER · v2.0 · 2026-10-20  
**Canonicity:** Canonical for package boundaries, dependencies, and licensing (`DOC_STRATEGY.md` §4)  
**Corpus Inventory:** [`docs/INDEX.md`](../INDEX.md)  

---

## 1. Overview & Tier Topology

`gargamelle` is partitioned into 11 modular Cabal packages across 6 architectural tiers. Each package maintains clear separation of concerns, zero-warning compilation under `-Wall -Werror` on GHC 9.14, and complete test isolation.

```
┌────────────────────────────────────────────────────────────────────────┐
│ TIER 5: Execution, Workflow & Orchestration                            │
│   ├── gargamelle-workflow  (Crem Mealy State Machine, Sheaf CEGIS Loop)│
│   └── gargamelle-sheaf     (Cellular Sheaves, Store Diffusion, H¹ Obs) │
├────────────────────────────────────────────────────────────────────────┤
│ TIER 4: Macro-Architecture & Logics                                    │
│   ├── gargamelle-core        (Kinded Institutions, Pushouts, Colimits) │
│   ├── gargamelle-fol         (Kinded FOL, Streaming Z3 Pipe, Refine)   │
│   ├── gargamelle-equational  (Equational Institution, Presheaf DPO)    │
│   ├── gargamelle-sandbox     (Bubblewrap Runtime, Resource Limits)     │
│   └── gargamelle-persistence (Beam SQLite Store, Run Tracking)         │
├────────────────────────────────────────────────────────────────────────┤
│ TIER 3: Semantic Verification                                          │
│   ├── gargamelle-model       (RuntimeModel, ObsMor, Free VerifierAST)  │
│   └── gargamelle-evidence    (Evidence Trees, hs-tree-sitter, Diff)    │
├────────────────────────────────────────────────────────────────────────┤
│ TIER 2: Calculi & Effect Pipelines                                     │
│   ├── gargamelle-logic       (LogicAST, Holes E[□_τ], AGContract Op)   │
│   └── gargamelle-effect      (Kernmantle Rope, O(1) Router, Fusion)     │
├────────────────────────────────────────────────────────────────────────┤
│ TIER 0 & 1: Substrate Peers (External)                                 │
│   ├── polytropos / plugin    (Flat Rep, Profunctor Optics, TcPlugin)   │
│   └── kernmantle             (Arrow Rope Effect Substrate)             │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Package Register

| Package | Tier | License | Synopsis | Key Modules | Primary Dependencies |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`gargamelle-logic`** | 2 | EUPL-1.2 | Pure syntax ASTs, order theory, and refinement calculi | `Gargamelle.Logic.AST`, `Gargamelle.Logic.Contract`, `Gargamelle.Logic.Galois` | `base`, `lattices`, `containers` |
| **`gargamelle-effect`** | 2 | EUPL-1.2 | Kernmantle Arrow Rope effect orchestration layer | `Effect.Rope`, `Effect.Strand`, `Gargamelle.Effect.Router`, `Gargamelle.Effect.Optics`, `Gargamelle.Effect.Fusion` | `base`, `kernmantle`, `polytropos-core`, `polytropos-profunctors`, `beam-core` |
| **`gargamelle-model`** | 3 | EUPL-1.2 | Observable runtime models and Free VerifierAST | `Gargamelle.Model.Observable`, `Gargamelle.Model.Verifier`, `Gargamelle.Model.Satisfaction` | `base`, `proarrow`, `contravariant`, `containers` |
| **`gargamelle-evidence`** | 3 | EUPL-1.2 | Evidence preservation and structural tree-diff AST tracking | `Evidence.AST`, `Evidence.Diff` | `base`, `text`, `hs-tree-sitter`, `tree-diff` |
| **`gargamelle-core`** | 4 | EUPL-1.2 | Categorical institutions, pushouts, and colimits | `Gargamelle.Core.Institution`, `Gargamelle.Core.Weaving`, `Gargamelle.Core.Discovery`, `Gargamelle.Core.Colimit` | `base`, `proarrow`, `proarrow-equipment`, `gargamelle-model` |
| **`gargamelle-fol`** | 4 | EUPL-1.2 | First-order logic institution and streaming Z3 SMT pipe | `FirstOrder`, `Hyperdoctrine`, `RefinementCalculus`, `Gargamelle.FOL.Z3` | `base`, `process`, `containers`, `gargamelle-model` |
| **`gargamelle-equational`**| 4 | EUPL-1.2 | Equational logic institution and presheaf DPO rewriting | `Equational`, `Gargamelle.Equational.DPO` | `base`, `proarrow`, `gargamelle-model` |
| **`gargamelle-sandbox`** | 4 | EUPL-1.2 | Bubblewrap container isolation and resource limits | `Sandbox.Effect`, `Sandbox.Handler` | `base`, `process`, `directory`, `filepath`, `unix` |
| **`gargamelle-persistence`**| 4 | EUPL-1.2 | Beam SQLite database persistence for runs and evidence | `Persistence.Schema`, `Persistence.Beam`, `Persistence.Queries` | `base`, `beam-core`, `beam-sqlite`, `sqlite-simple` |
| **`gargamelle-sheaf`** | 5 | EUPL-1.2 | Cellular sheaves, Store comonad diffusion, and H¹ obstruction localization | `Gargamelle.Sheaf`, `Gargamelle.Sheaf.Complex`, `Gargamelle.Sheaf.Diffusion`, `Gargamelle.Sheaf.Cohomology` | `base`, `comonad`, `lattices`, `gargamelle-core`, `gargamelle-model` |
| **`gargamelle-workflow`** | 5 | EUPL-1.2 | Synthesis workflow, Crem Mealy state machine, and sheaf-gated CEGIS loop | `Workflow.Synthesis` | `base`, `crem`, `singletons-base`, `tree-diff`, `gargamelle-sheaf`, `gargamelle-sandbox`, `gargamelle-persistence` |

---

## 3. Peer Repositories & Upstream Provenance

| Project | Location | License | Integration Purpose |
| :--- | :--- | :--- | :--- |
| **`polytropos`** | `../polytropos` | EUPL-1.2 | Flat `Rep` unboxed array substrate, profunctor lenses/prisms, TcPlugin literal indexing |
| **`kernmantle`** | `../kernmantle` | BSD-3-Clause | Arrow `Rope` effect pipelines, variant multi-branching (`routeVariantWith`), Coyoneda arrow fusion |
| **`proarrow`** | `../proarrow` | BSD-3-Clause | Category theory, profunctor equipment, Day convolution, and Double-Pushout (DPO) rewriting |
| **`beam`** | `../beam` | MIT | Type-safe backend-agnostic database schemas (`beam-core`, `beam-sqlite`) |
| **`crem`** | `../crem` | BSD-3-Clause | Formally verified Mealy state machines with singletons-base topology verification |
| **`tree-diff`** | `../tree-diff` | BSD-3-Clause | Grounded structural expression diffing and AST similarity metric |
| **`hs-tree-sitter`** | `../hs-tree-sitter` | BSD-3-Clause | High-performance C FFI Tree-sitter grammar parsers for structural code analysis |
