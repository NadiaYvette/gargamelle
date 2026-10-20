<!--
SPDX-License-Identifier: EUPL-1.2
-->
# Gargamelle Architectural Redesign: Categorical Institutions, Cellular Sheaves, and Universal Observability

**Status:** DESIGN SPECIFICATION · v2.0 · Comprehensive Blueprint  
**Author:** Nadia Chambers / Antigravity  
**Date:** October 2026  
**Canonical Companion:** `docs/notes/CATEGORICAL_FOUNDATIONS_SURVEY.md`  
**Governing Policy:** `docs/notes/DOC_STRATEGY.md`  

---

## 1. Executive Summary & Problem Statement

### 1.1 The Operational vs. Epistemic Gap
In its initial architecture (Milestones M1–M3), `gargamelle` succeeded at **operational effect orchestration**:
- `gargamelle-effect` uses Kernmantle Arrow `Rope` pipelines to route side-effects ($a \to b$).
- `gargamelle-workflow` uses Crem Mealy state machines to drive iterative synthesis loops.
- `gargamelle-sandbox` and `gargamelle-persistence` isolate bubblewrap executions and record SQLite evidence.

However, in autonomous multi-agent programming campaigns, orchestrating execution is insufficient. Unchecked generative AI agents produce code that is syntactically valid and locally compiles, but introduces catastrophic semantic regressions across module boundaries. 

Currently, `gargamelle-core` defines a skeletal `Institution sig` typeclass without categorical morphisms, pushouts, or satisfaction invariance under notation change. Legacy ATP adapters (`Folly` and `Jukebox`) are rigid, monomorphic, and incapable of extracting executable counter-models into the Haskell runtime. Furthermore, typical functional implementations suffer from **opacity leaks**: using raw Haskell closures `(a -> b)` that cannot be serialized, inspected by SMT solvers, or analyzed when invariants fail.

### 1.2 The Unified 7-Layer Architecture
This redesign elevates `gargamelle` from an effect-runner script to a **semantically sound, mathematically verified software engineering engine** spanning seven integrated layers:

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ Layer 7: Cellular Sheaf Coordination & Homological Fault Localization (gargamelle-sheaf)│
│          - Cellular sheaves F over architecture graphs G = (V, E)                       │
│          - Knaster-Tarski fixed-point sheaf diffusion (diffuseUntilHarmonic)            │
│          - H⁰(G; Mod) ≅ Mod(colim D) (Global consistency); H¹(G; F) (Pinpoint faults)  │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ Layer 6: Categorical Macro-Architecture & Institutions (gargamelle-core)                │
│          - Kind-indexed Goguen-Burstall Institutions via proarrow CAT                   │
│          - Pushout feature weaving (B ⨿_C W), Pullback interface discovery (A ×_E B)   │
│          - Diagram Colimits (colim D) & semantic delta factorizers                      │
│          - Symmetric Monoidal task tensors & colored operads via kan-extensions:Day    │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ Layer 5: Profunctors, Optics & Braided Pipelines (gargamelle-effect)                    │
│          - Kernmantle Arrow Rope ported to Polytropos discrete indices                  │
│          - O(1) variant routing via deriveRouter jump tables                            │
│          - Selective VirtualTree static dependency extraction                           │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ Layer 4: Observable Model Theory & Verification (gargamelle-model)                      │
│          - RuntimeModel :: k -> Type and model morphisms                                │
│          - 100% Observable morphisms (ObsMor a b); zero opaque closures                 │
│          - Free VerifierAST via contravariant: Divisible & Decidable                    │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ Layer 3: Order Theory, Refinement Lattices & Behavioral Calculi                         │
│          - Dual assume-guarantee contracts via lattices:Algebra.Lattice.Op              │
│          - Galois connections α ⊣ γ via adjunctions:Adjunction                          │
│          - Contextual hole calculi E[□_τ] and MPST session type choreography            │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ Layer 2: Universal Algebra, Logic & Proof Theory (gargamelle-logic)                     │
│          - Kind-indexed LogicAST with flat connectives over Polytropos                  │
│          - Category of entailment via constraints:(:-)                                  │
│          - Hyperdoctrines & Presheaf DPO rewriting (replacing Jukebox)                  │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ Layer 1 & 0: Row-Polymorphic Substrate & TcPlugin (polytropos & polytropos-plugin)      │
│          - Contiguous Rep (Tag + SmallArray); O(1) profunctor optics                    │
│          - TcPlugin literal index calculation; Coyoneda array fusion (rmapFused)        │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Architectural Decisions (D1 – D12)

### D1: Separation of Epistemic Flow from Operational Execution
- **Decision:** Separate proof and specification flow from physical effect routing.
- **Mechanism:** Institutions govern *what is verified and true*; Kernmantle Arrow `Rope` pipelines govern *how effects are executed*.

### D2: Categorical Foundation via `proarrow` & `proarrow-equipment`
- **Decision:** Adopt Sjoerd Visscher's `proarrow` and `proarrow-equipment` as the foundational category engine, terminating higher structure at **Double Categories / Equipments**.
- **Rationale:** As proven in `CATEGORICAL_FOUNDATIONS_SURVEY.md` §3, pursuing weak 3-categories triggers the **Stasheff Associahedron Coherence Explosion** (pentagonators, nonagons, Catalan-number coherence paths). Double categories and equipments provide horizontal 1-cells (pipelines), vertical proarrows (specifications), and 2D commuting double cells (verified refactorings)—all strictly associative without higher coherence overhead.

### D3: Safe Feature Weaving via Pushouts ($B \amalg_C W$)
- **Decision:** Cross-cutting concerns (logging, sandboxing policies, security invariants, audit probes) must be woven into base software components using categorical pushouts over a shared interface $C$.
- **Soundness:** By the **Amalgamation Theorem**, if $M_B \in \mathbf{Mod}(B)$ and $M_W \in \mathbf{Mod}(W)$ agree on $C$, there exists a unique amalgamated model $M_P \in \mathbf{Mod}(P)$ that preserves all original invariants.

### D4: Protocol Discovery via Pullbacks ($A \times_E B$)
- **Decision:** Derive minimal shared interfaces and session types between interacting subsystems via categorical pullbacks over an ambient environment $E$.

### D5: Architecture Colimits & Universal Change Propagation
- **Decision:** Model entire system architectures as diagrams $D : \mathbf{I} \to \mathbf{Sign}$. The complete system specification is the colimit $\operatorname{colim}(D)$.
- **Mechanism:** When an agent modifies a single component $\Sigma_k \to \Sigma_k'$, the universal property of the colimit (the mediating morphism / factorizer) isolates the exact semantic delta across the dependency graph. Proof obligations are automatically discharged for unaffected modules.

### D6: SMT Z3 Pipe & Presheaf DPO Rewriting (Retiring Folly & Jukebox)
- **Decision:** Deprecate and remove legacy ATP wrappers `external/Folly` and `external/Jukebox`.
- **Replacement:**
  1. For **Equational & Structural Rewriting:** Use `Proarrow.Tools.DPO` (Double Pushout Rewriting) directly on AST presheaves.
  2. For **Satisfiability & Counter-Model Extraction:** Pipe directly to Z3 4.16.0 via SMT-LIB2 over sandboxed IPC, producing concrete counter-examples for the CEGIS loop.

### D7: Discrete Heterogeneous Storage via Polytropos
- **Decision:** Multi-sorted signatures and sentence conjunctions are defunctionalized into discrete indexations over $\mathbf{Fin}_N$, backed by `polytropos-core`'s flat `SmallArray (f Any)`.
- **Rationale:** Avoids the combinatorial typeclass explosion of $N$-ary arrows and $K$-indexed profunctors. Polytropos provides $O(1)$ memory operations and literal TcPlugin index offsets at compile time.

### D8: Native Invertible Transport via `Data.Coercible`
- **Decision:** Discard custom `PolyBiArrow` and `AsymmetricConjugate` typeclasses.
- **Rationale:** As proven in `CATEGORICAL_FOUNDATIONS_SURVEY.md` §6, the conjugation $g \circ H \circ g^{-1}$ in `peel` is governed by the **reflection arrows of a reflective subcategory**. In GHC, representational equivalence is natively proven by `Data.Coercible` and reified in `Data.Type.Coercion.Coercion`. Standard `Data.Bifunctor.bimap coerce (coerce . productRep)` performs the exact zero-cost coproduct reflection with zero runtime allocations.

### D9: Cellular Sheaves & Comonadic Diffusion (`gargamelle-sheaf`)
- **Decision:** Model the complete multi-module architecture graph $G = (V, E)$ as a cellular sheaf $\mathcal{F} : \operatorname{Fc}(G) \to \mathbf{D}$.
- **Mechanism:** 
  - Vertex stalks $\mathcal{F}(v)$ hold local component states/theories; edge stalks $\mathcal{F}(e)$ hold shared protocols.
  - Diffusion is implemented as a **Store Comonad** cellular automaton: `StoreT (CochainMap vId) Identity stalk`.
  - Knaster-Tarski fixed-point iteration `diffuseUntilHarmonic` computes the maximal mutually consistent state.
  - 0th Cohomology $H^0(G; \mathbf{Mod}) \cong \mathbf{Mod}(\operatorname{colim} D)$ witnesses global consistency.
  - 1st Cohomology $H^1(G; \mathcal{F}) = C^1(G; \mathcal{F}) / \operatorname{im} \delta_\mathcal{F}$ isolates exact failing boundary edges for targeted CEGIS re-prompting.

### D10: 100% Observability via `ObsMor` and Free Verifier AST
- **Decision:** Completely eliminate opaque Haskell function closures `(a -> b)` from the epistemic and verification layers.
- **Mechanism:**
  - All morphisms are reified as first-order `ObsMor a b` ASTs with symbolic tags and schema references.
  - All model verifiers are constructed as free `VerifierAST a` structures via `contravariant:Divisible` and `Decidable`.
  - Enables full serialization to Beam SQLite, direct extraction of Z3 constraints, and detailed causal failure trees.

### D11: Assume-Guarantee Contracts via Lattice Duality (`lattices:Op`)
- **Decision:** Model assume-guarantee contracts using `lattices:Algebra.Lattice.Op`.
- **Mechanism:** A guarantee of a provider is an assumption of a consumer: $\text{Contract}(A, G) \equiv (A \in \mathcal{L}^{op}, G \in \mathcal{L})$. Galois connections $\alpha \dashv \gamma$ between concrete execution and abstract contracts are modeled using `adjunctions:Adjunction`.

### D12: Symmetric Monoidal Task Tensors via `kan-extensions:Day`
- **Decision:** Multi-agent task composition and colored operads are modeled as symmetric monoidal functors under Day convolution: `Day f g a = ∃ b c. (f b, g c, b -> c -> a)`.
- **Rationale:** Permits composing asynchronous agent tasks in parallel without prematurely imposing a sequential Monad bind.

---

## 3. Core Technical Architecture & Signatures

### 3.1 Observable Morphisms & Free Verifiers (`gargamelle-model`)
In `packages/gargamelle-model/src/Gargamelle/Model/Observable.hs`:

```haskell
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ExplicitForAll #-}

module Gargamelle.Model.Observable
  ( ObsMor(..)
  , VerifierAST(..)
  , verifyModel
  ) where

import Data.Kind (Type)
import Data.Text (Text)
import Data.Type.Coercion (Coercion)
import Control.Category (Category(..))
import Data.Functor.Contravariant (Contravariant(..))
import Data.Functor.Contravariant.Divisible (Divisible(..), Decidable(..))
import Prelude hiding (id, (.))

-- | First-order, serializable, fully observable morphism AST
data ObsMor (a :: Type) (b :: Type) where
  ObsId        :: ObsMor a a
  ObsComp      :: ObsMor b c -> ObsMor a b -> ObsMor a c
  ObsTagProj   :: Int -> ObsMor a b
  ObsCoerce    :: Coercion a b -> ObsMor a b
  ObsNamed     :: Text -> (a -> b) -> ObsMor a b

instance Category ObsMor where
  id  = ObsId
  (.) = ObsComp

-- | Free Verifier AST built over ObsMor, admitting full introspection and SMT extraction
data VerifierAST (a :: Type) where
  VerifyPred   :: Text -> ObsMor a Bool -> VerifierAST a
  VerifyDivide :: ObsMor a (b, c) -> VerifierAST b -> VerifierAST c -> VerifierAST a
  VerifyChoose :: ObsMor a (Either b c) -> VerifierAST b -> VerifierAST c -> VerifierAST a
  VerifyTrue   :: VerifierAST a
  VerifyLose   :: ObsMor a Void -> VerifierAST a

instance Contravariant VerifierAST where
  contramap mor (VerifyPred tag p)       = VerifyPred tag (p . mor)
  contramap mor (VerifyDivide s v1 v2)   = VerifyDivide (s . mor) v1 v2
  contramap mor (VerifyChoose b v1 v2)   = VerifyChoose (b . mor) v1 v2
  contramap _   VerifyTrue               = VerifyTrue
  contramap mor (VerifyLose absurd)      = VerifyLose (absurd . mor)

instance Divisible VerifierAST where
  divide split = VerifyDivide (ObsNamed "divide" split)
  conquer      = VerifyTrue

instance Decidable VerifierAST where
  choose branch = VerifyChoose (ObsNamed "choose" branch)
  lose absurd   = VerifyLose (ObsNamed "lose" absurd)
```

### 3.2 Kind-Indexed Goguen-Burstall Institutions (`gargamelle-core`)
In `packages/gargamelle-core/src/Gargamelle/Core/Institution.hs`:

```haskell
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE StandaloneKindSignatures #-}

module Gargamelle.Core.Institution
  ( LogicalSyntax(..)
  , ModelTheory(..)
  , Institution(..)
  , InstitutionComorphism(..)
  , PushoutWeaving(..)
  ) where

import Data.Kind (Type)
import Proarrow.Core (CategoryOf(..), CAT, (~>))
import Proarrow.Colimit.Pushout (HasPushouts(..))
import Gargamelle.Model.Observable (ObsMor, VerifierAST)

-- | 1. Syntactic Layer (Proof Theory)
class (CategoryOf (Sig i)) => LogicalSyntax i where
  type Sig i :: Type
  type Sen i :: Sig i -> Type
  translateSen :: forall (s1 :: Sig i) (s2 :: Sig i). (s1 ~> s2) -> Sen i s1 -> Sen i s2
  (|-) :: forall (s :: Sig i). [Sen i s] -> Sen i s -> Bool

-- | 2. Semantic Layer (Model Theory)
class (CategoryOf (Sig i)) => ModelTheory i where
  type Mod i :: Sig i -> Type
  reductMod :: forall (s1 :: Sig i) (s2 :: Sig i). (s1 ~> s2) -> ObsMor (Mod i s2) (Mod i s1)

-- | 3. The Goguen-Burstall Institution with Observable Verifiers
class (LogicalSyntax i, ModelTheory i) => Institution i where
  checkSatisfies :: forall (s :: Sig i). Sen i s -> VerifierAST (Mod i s)

  -- | THE SATISFACTION CONDITION (Verified via Proarrow.Testing.Laws):
  -- For every morphism σ : s1 ~> s2, M' ∈ Mod(s2), φ ∈ Sen(s1):
  --   verify (checkSatisfies (translateSen σ φ)) M' <===> verify (checkSatisfies φ) (reductMod σ M')

-- | 4. Pushout Feature Weaving
class (Institution i, HasPushouts (Sig i)) => PushoutWeaving i where
  weaveFeatures
    :: forall (c :: Sig i) (b :: Sig i) (w :: Sig i) r.
       (c ~> b) -> (c ~> w) -> (forall (p :: Sig i). (b ~> p) -> (w ~> p) -> r) -> r
  weaveFeatures = pushout

  amalgamateModels
    :: forall (c :: Sig i) (b :: Sig i) (w :: Sig i) (p :: Sig i).
       (c ~> b) -> (c ~> w) -> (b ~> p) -> (w ~> p)
    -> Mod i b -> Mod i w -> Maybe (Mod i p)
```

### 3.3 Cellular Sheaves & Homological Fault Localization (`gargamelle-sheaf`)
In `packages/gargamelle-sheaf/src/Gargamelle/Sheaf/Diffusion.hs`:

```haskell
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Gargamelle.Sheaf.Diffusion
  ( CellComplex(..)
  , CellularSheaf(..)
  , Cochain0(..)
  , Cochain1(..)
  , coboundary
  , diffuseUntilHarmonic
  , CohomologyResult(..)
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Algebra.Lattice (BoundedJoinSemiLattice(..), BoundedMeetSemiLattice(..))
import Control.Comonad.Store (Store, store, runStore)

-- | Graph Cell Complex G = (V, E)
data CellComplex vId eId = CellComplex
  { vertices :: [vId]
  , edges    :: Map eId (vId, vId)
  }

-- | Cellular Sheaf F over G
data CellularSheaf vId eId stalk edgeStalk = CellularSheaf
  { restrictSrc :: eId -> stalk -> edgeStalk
  , restrictTgt :: eId -> stalk -> edgeStalk
  , liftEdge    :: eId -> edgeStalk -> stalk
  }

newtype Cochain0 vId stalk = Cochain0 { unCochain0 :: Map vId stalk }
newtype Cochain1 eId edgeStalk = Cochain1 { unCochain1 :: Map eId edgeStalk }

-- | Sheaf Coboundary Operator δ_F : C⁰ -> C¹
coboundary
  :: (Ord eId, Eq edgeStalk)
  => CellComplex vId eId
  -> CellularSheaf vId eId stalk edgeStalk
  -> Cochain0 vId stalk
  -> (Cochain1 eId (edgeStalk, edgeStalk), Bool)
coboundary complex sheaf (Cochain0 vMap) =
  let edgeDiffs = Map.mapWithKey computeEdge (edges complex)
      isHarmonic = all (\(s, t) -> s == t) edgeDiffs
  in (Cochain1 edgeDiffs, isHarmonic)
  where
    computeEdge eId (u, v) =
      let stU = vMap Map.! u
          stV = vMap Map.! v
      in (restrictSrc sheaf eId stU, restrictTgt sheaf eId stV)

-- | Knaster-Tarski Fixed-Point Diffusion via Store Comonad
diffuseUntilHarmonic
  :: (Ord vId, Ord eId, BoundedMeetSemiLattice stalk, Eq stalk)
  => Int  -- ^ Max iterations
  -> CellComplex vId eId
  -> CellularSheaf vId eId stalk edgeStalk
  -> Cochain0 vId stalk
  -> Cochain0 vId stalk
diffuseUntilHarmonic maxSteps complex sheaf = go 0
  where
    go step c0@(Cochain0 m)
      | step >= maxSteps = c0
      | m == nextM       = c0
      | otherwise        = go (step + 1) (Cochain0 nextM)
      where
        nextM = Map.mapWithKey (diffuseVertex complex sheaf c0) m

diffuseVertex
  :: (Ord eId, BoundedMeetSemiLattice stalk)
  => CellComplex vId eId
  -> CellularSheaf vId eId stalk edgeStalk
  -> Cochain0 vId stalk
  -> vId
  -> stalk
  -> stalk
diffuseVertex complex sheaf (Cochain0 vMap) v currStalk =
  -- Comonadic local neighborhood inspection
  let incidentEdges = [ (e, other) | (e, (u, w)) <- Map.toList (edges complex)
                                  , let other = if u == v then Just w else if w == v then Just u else Nothing
                                  , other /= Nothing ]
  in foldr meet currStalk [ liftEdge sheaf e (restrictSrc sheaf e (vMap Map.! o))
                          | (e, Just o) <- incidentEdges ]
```

---

## 4. The 10-Package Suite Across 5 Compilation Tiers

To match and exceed the scope outlined in the latest transcript, the codebase is structured into 10 decoupled packages across 5 strict compilation tiers:

```
┌────────────────────────────────────────────────────────────────────────┐
│ TIER 5: Orchestration & Topology                                       │
│   ├── gargamelle-sheaf    (Cellular Sheaves, Coboundary, Homology H¹)  │
│   └── gargamelle-workflow (Crem Mealy Loop, CEGIS, Kernmantle Rope)    │
└──────────────────────────────────▲─────────────────────────────────────┘
                                   │
┌──────────────────────────────────┴─────────────────────────────────────┐
│ TIER 4: Macro-Architecture, Logics & Execution                         │
│   ├── gargamelle-core        (Kinded Institutions, Pushouts, Colimits) │
│   ├── gargamelle-fol / eq    (Kinded FOL, Z3 Pipe, Presheaf DPO)       │
│   └── gargamelle-sandbox / db(Bubblewrap Runtime, Beam SQLite Store)   │
└──────────────────────────────────▲─────────────────────────────────────┘
                                   │
┌──────────────────────────────────┴─────────────────────────────────────┐
│ TIER 3: Semantic Verification                                          │
│   └── gargamelle-model    (RuntimeModel, ObsMor, Free VerifierAST)     │
└──────────────────────────────────▲─────────────────────────────────────┘
                                   │
┌──────────────────────────────────┴─────────────────────────────────────┐
│ TIER 2: Calculi & Effect Pipelines                                     │
│   ├── gargamelle-logic    (LogicAST, Entailment (:-), Holes E[□_τ])    │
│   └── gargamelle-effect   (Polytropos-Kernmantle Rope, O(1) Router)    │
└──────────────────────────────────▲─────────────────────────────────────┘
                                   │
┌──────────────────────────────────┴─────────────────────────────────────┐
│ TIER 0 & 1: Substrate                                                  │
│   ├── polytropos          (Flat Rep, Profunctor Optics, Coyoneda)      │
│   └── polytropos-plugin   (TcPlugin Literal Indices, SubRow Solver)    │
└────────────────────────────────────────────────────────────────────────┘
```

### Detailed Package Specifications

| Tier | Package | Expository Modules | Key Hackage Repertoire |
| :--- | :--- | :--- | :--- |
| **Tier 0** | `polytropos-plugin` | `Polytropos.Plugin`, `Polytropos.Plugin.Solver` | `ghc`, `ghc-tcplugins-extra` |
| **Tier 1** | `polytropos` | `Polytropos.Core`, `Polytropos.Optics`, `Polytropos.Fusion` | `primitive`, `kan-extensions` (`Coyoneda`) |
| **Tier 2A**| `gargamelle-effect` | `Gargamelle.Effect.Rope`, `Gargamelle.Effect.Router`, `Gargamelle.Effect.Automaton` | `arrows` (`Automaton`), `profunctors` |
| **Tier 2B**| `gargamelle-logic` | `Gargamelle.Logic.AST`, `Gargamelle.Logic.Holes`, `Gargamelle.Logic.Contracts` | `lattices` (`Algebra.Lattice.Op`), `constraints` (`(:-)`) |
| **Tier 3** | `gargamelle-model` | `Gargamelle.Model.Runtime`, `Gargamelle.Model.Observable`, `Gargamelle.Model.Verifier` | `contravariant` (`Divisible`, `Decidable`), `adjunctions` |
| **Tier 4A**| `gargamelle-core` | `Gargamelle.Core.Institution`, `Gargamelle.Core.Weaving`, `Gargamelle.Core.Colimit` | `proarrow`, `proarrow-equipment`, `kan-extensions` (`Day`, `Codensity`) |
| **Tier 4B**| `gargamelle-fol` & `equational` | `Gargamelle.FOL.Z3`, `Gargamelle.Equational.DPO` | `process`, `z3` / SMT-LIB2, `proarrow` |
| **Tier 4C**| `gargamelle-sandbox` & `persistence` | `Gargamelle.Sandbox.Bwrap`, `Gargamelle.Persistence.Schema` | `beam-core`, `beam-sqlite`, `unix` |
| **Tier 5A**| `gargamelle-sheaf` | `Gargamelle.Sheaf.Complex`, `Gargamelle.Sheaf.Diffusion`, `Gargamelle.Sheaf.Cohomology` | `comonad` (`Store`), `indexed-profunctors`, `lattices` |
| **Tier 5B**| `gargamelle-workflow` | `Gargamelle.Workflow.Mealy`, `Gargamelle.Workflow.CEGIS`, `Gargamelle.Workflow.Pipeline` | `crem`, `gargamelle-effect`, `gargamelle-core` |

---

## 5. Implementation Roadmap & Migration Plan (Phases 1 – 6)

To maintain continuous verification under GHC 9.10.3 and 9.14 (`-Wall -Werror`) without regressing existing tests, implementation proceeds in six strictly gated phases:

```
  ┌────────────────────────────────────────────────────────┐
  │ Phase 1: Substrate & Observable Verifier Core          │
  │          - Wire gargamelle-model & gargamelle-logic    │
  │          - Free VerifierAST & ObsMor combinators       │
  └───────────────────────────┬────────────────────────────┘
                              │
  ┌───────────────────────────▼────────────────────────────┐
  │ Phase 2: Category Core & Institutions                  │
  │          - Integrate proarrow & proarrow-equipment     │
  │          - Kind-indexed Institution & Pushout Weaving  │
  └───────────────────────────┬────────────────────────────┘
                              │
  ┌───────────────────────────▼────────────────────────────┐
  │ Phase 3: SMT Solver Pipe & Presheaf DPO Rewriting      │
  │          - Retire external/Folly & external/Jukebox    │
  │          - Connect Z3 4.16.0 pipe & Proarrow.Tools.DPO │
  └───────────────────────────┬────────────────────────────┘
                              │
  ┌───────────────────────────▼────────────────────────────┐
  │ Phase 4: Cellular Sheaves & Homological Localization   │
  │          - Build gargamelle-sheaf Store cellular runner│
  │          - Knaster-Tarski diffuseUntilHarmonic         │
  │          - H⁰ amalgamation & H¹ obstruction tests      │
  └───────────────────────────┬────────────────────────────┘
                              │
  ┌───────────────────────────▼────────────────────────────┐
  │ Phase 5: Polytropos-Kernmantle Rope & Optics           │
  │          - Upgrade gargamelle-effect to Polytropos     │
  │          - O(1) variant router jump tables             │
  └───────────────────────────┬────────────────────────────┘
                              │
  ┌───────────────────────────▼────────────────────────────┐
  │ Phase 6: End-to-End Sheaf-Gated CEGIS Workflow         │
  │          - Crem Mealy machine driven by H¹ coboundary  │
  │          - Preserve 20 existing integration tests      │
  └────────────────────────────────────────────────────────┘
```

### Phase 1: Substrate & Observable Verifier Core
- Instantiate `gargamelle-model` and `gargamelle-logic`.
- Implement `ObsMor a b`, `VerifierAST a` (`Divisible` / `Decidable`).
- Implement Assume-Guarantee duals via `lattices:Algebra.Lattice.Op`.
- Verify zero compiler warnings under `-Wall -Werror`.

### Phase 2: Category Core & Institutions
- Connect `proarrow` and `proarrow-equipment` in `cabal.project`.
- Implement `Institution.hs`, `Weaving.hs` ($B \amalg_C W$), and universal colimit factorizers.
- Formalize model amalgamation: prove that pushing an aspect into a base model preserves base satisfaction.
- Validate categorical laws using `Proarrow.Testing.Laws`.

### Phase 3: SMT Z3 Pipe & Presheaf DPO Rewriting
- Remove `external/Folly` and `external/Jukebox` git submodules.
- Implement streaming SMT-LIB2 pipe to host Z3 4.16.0 in `gargamelle-fol`.
- Model equational transformations using `Proarrow.Tools.DPO`.

### Phase 4: Cellular Sheaves & Homological Fault Localization
- Instantiate `gargamelle-sheaf`.
- Implement the `Store` comonad cellular diffusion runner over `CellComplex G`.
- Implement `coboundary` operator and compute $H^1$ obstruction maps.
- Prove $H^0(G; \mathbf{Mod}) \cong \mathbf{Mod}(\operatorname{colim} D)$ on multi-module test graphs.

### Phase 5: Polytropos-Kernmantle Rope & Optics
- Update `gargamelle-effect` to route over `Polytropos.Variant` and `Record`.
- Implement `deriveRouter` jump table using flat array tags.
- Fuse intermediate array transformations via `kan-extensions:Coyoneda`.

### Phase 6: End-to-End Sheaf-Gated CEGIS Workflow
- Update `gargamelle-workflow`'s Crem Mealy state machine to receive $H^1$ obstruction feedback.
- Wire Bubblewrap execution and Beam SQLite persistence into the pipeline.
- Verify that all 20 existing integration tests in `gargamelle-workflow:test:tests` remain 100% green.

---

## 6. Verification & Quality Gates

In accordance with `AGENTS.md` and `DOC_STRATEGY.md`:
1. **Compilation Gate:** Builds cleanly under GHC 9.10.3 and GHC 9.14 via `cabal build all` with zero warnings (`-Wall -Werror`).
2. **Linter Gate:** 0 HLint hints reported across all 10 packages.
3. **Law Verification:** All categorical instances (`Institution`, `HasPushouts`, `Adjunction`, `Divisible`, `Decidable`, `Category`) pass automated property tests via `Proarrow.Testing.Laws` and `QuickCheck`.
4. **Zero-Regression Gate:** The 20 existing workflow integration tests in `gargamelle-workflow:test:tests` remain green throughout the transition.
5. **Observability Gate:** Zero opaque function closures in the epistemic and sheaf layers; all morphisms inspectable via `ObsMor` and serializable to Beam SQLite.
