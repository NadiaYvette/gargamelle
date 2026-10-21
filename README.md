# Gargamelle

**Autonomous Synthesis Orchestration, Categorical Institutions, Cellular Sheaves, and Homological Fault Localization for Haskell.**

**Mirrors:** [GitHub](https://github.com/NadiaYvette/gargamelle) · [GitCode](https://gitcode.com/NadiaYvette/gargamelle) · [Disroot](https://git.disroot.org/NadiaYvette/gargamelle) · [Framagit](https://framagit.org/NadiaYvette/gargamelle) · [Radicle Web](https://radicle.network/nodes/iris.radicle.network/rad:zqykaqjnoA8a1harMdQVsigC7VwH)

`gargamelle` is a formally grounded, multi-tier Haskell engine designed to orchestrate autonomous programming and program synthesis campaigns at scale. It synthesizes, verifies, executes, and repairs software systems across heterogeneous domains by combining:
1. **Goguen-Burstall Institutions & Pushouts (`gargamelle-core`):** Universal semantics and non-invasive feature weaving ($B \amalg_C W$) preserving satisfaction across arbitrary logics.
2. **Homological Fault Localization via Cellular Sheaves (`gargamelle-sheaf`):** Topological obstruction theory mapping failing cross-module boundaries directly to non-vanishing $H^1$ cohomology classes.
3. **Knaster-Tarski Consensus Diffusion via the Store Comonad (`gargamelle-sheaf`):** Comonadic cellular diffusion over contract lattices converging to greatest lower bound agreements.
4. **100% Observable Verifiers (`gargamelle-logic`, `gargamelle-model`):** First-order reified morphisms (`ObsMor`) and Free `VerifierAST`s completely eliminating opaque `(->)` closures.
5. **Streaming SMT Pipe & Presheaf DPO Rewriting (`gargamelle-fol`, `gargamelle-equational`):** Native first-order logic interfacing with host Z3 4.16 and Double-Pushout algebraic graph rewriting.
6. **Effect Orchestration & Profunctor Optics (`gargamelle-effect`):** Kernmantle Arrow `Rope` effect pipelines, $O(1)$ variant jump-table routing, and Coyoneda pipeline fusion.
7. **Grounded Sandbox Isolation & Beam Persistence (`gargamelle-sandbox`, `gargamelle-persistence`):** Linux container namespace sandboxing via Bubblewrap (`/usr/bin/bwrap`) and structured SQLite evidence storage via Beam.
8. **End-to-End Sheaf-Gated CEGIS (`gargamelle-workflow`):** Formally verified Crem Mealy state machines orchestrating counterexample-guided inductive synthesis loops gated by $H^1$ coboundary obstruction analysis.

---

## The Name

The library takes its name from François Rabelais’ 1534 masterpiece *Gargantua* (the second book of the *Gargantua and Pantagruel* pentalogy). **Gargamelle** is the daughter of the King of the Amaurotes and the mother of the giant Gargantua.

In Rabelaisian literature, Gargamelle evokes the **"Mother of Giants"**—a generative, overarching force capable of giving birth to monumental entities. In this architecture, *Gargamelle* acts as the mother orchestrator: the foundational epistemic substrate that synthesizes, coordinates, verifies, and repairs complex software architectures too vast for manual human coordination alone.

---

## Motivation & Architecture: Concepts in Plain English

For software engineers, compiler authors, and logicians, Gargamelle bridges the gap between deep category theory and physical container execution:

### 1. What Is an Autonomous Programming Campaign?
An autonomous programming campaign is an automated process where an AI or synthesis engine iteratively generates, compiles, tests, and refines software patches. Traditional pipelines fail at scale because they treat programs as black-box strings: when an integration fails, the synthesizer receives an opaque compiler error or test stack trace with no understanding of which architectural contract was violated. Gargamelle provides a rich mathematical framework that pinpoints the exact boundary failure.

### 2. What Is a Categorical Institution? (In Plain English)
Formalized by Joseph Goguen and Rod Burstall (1992), an **Institution** is the category-theoretic formalization of a "logical system." It separates:
- **Signatures ($\mathbf{Sig}$):** The vocabulary of types, function names, and module interfaces.
- **Sentences ($\mathbf{Sen}$):** The formulas, propositions, or types that can be expressed over a signature.
- **Models ($\mathbf{Mod}$):** The concrete implementations, values, or runtimes that interpret a signature.
- **The Satisfaction Condition:** If an implementation $M'$ satisfies a specification $\sigma(\phi)$ translated along an interface mapping $\sigma$, it must be that the reduced implementation $\sigma^*(M')$ satisfies the original specification $\phi$.

By formulating logics as Institutions (`gargamelle-core`), Gargamelle allows programs in different languages and logics (First-Order Logic, Equational Logic, Session Types, Refinement Calculi) to be composed, translated via *comorphisms*, and woven together using **Categorical Pushouts** ($B \amalg_C W$).

### 3. What Is Homological Fault Localization via Cellular Sheaves?
In complex multi-module systems, each service or component satisfies local contracts, but the composed system can diverge at the boundaries. 
- We model the software architecture as a **1-dimensional Cell Complex** $G = (V, E)$, where 0-cells $V$ are modules and 1-cells $E$ are shared interfaces.
- A **Cellular Sheaf** $\mathcal{F}$ assigns stalks (local contract specifications or states) to vertices and edges, along with restriction maps $\rho_{u \trianglelefteq e}, \rho_{v \trianglelefteq e}$.
- The **Sheaf Coboundary Operator** $\delta^0 : C^0(G; \mathcal{F}) \to C^1(G; \mathcal{F})$ compares restrictions along every edge:
  $$\delta^0(x)_e = \rho_{v \trianglelefteq e}(x_v) - \rho_{u \trianglelefteq e}(x_u)$$
- **Harmonic Global Sections ($H^0 = \ker \delta^0$):** If the coboundary vanishes everywhere ($\delta^0 = 0$), the local implementations seamlessly glue into a globally coherent system. By the **Model Amalgamation Theorem**, $H^0(G; \mathbf{Mod}) \cong \mathbf{Mod}(\operatorname{colim} D)$.
- **$H^1$ Obstructions:** When interfaces mismatch, the non-vanishing edge discrepancies form $H^1$ cohomology classes. Gargamelle's `locateObstructions` pinpoints the exact edges $e \in E$ and mismatching contracts $(s \neq t)$, feeding targeted counterexamples directly into the CEGIS repair loop.

### 4. What Is Store Comonad Cellular Diffusion?
Instead of immediately aborting when boundaries disagree, Gargamelle treats the cellular complex as a **Store Comonad** (`Control.Comonad.Store`). Using comonadic `extend`, each vertex inspects its neighbors across incident boundaries and computes the meet ($\wedge$) in a contract lattice (`Algebra.Lattice.Op`). By the **Knaster-Tarski Theorem**, iterating this diffusion (`diffuseUntilHarmonic`) is guaranteed to converge to the greatest lower bound consensus.

### 5. Why 100% Observable Morphisms (`ObsMor`)?
In standard Haskell, morphisms are opaque functions `(a -> b)` that cannot be serialized, inspected, or converted to SMT formulas. `gargamelle-model` and `gargamelle-logic` reify morphisms into deep ASTs (`ObsMor`), enabling:
- Complete static introspection of verification plans (`inspectVerifierPlan`).
- Direct translation to SMT-LIB2 queries for host Z3 4.16.
- Persistent serialization into SQLite via Beam.

---

## Architectural Tier Map

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

## The 11 Packages Suite

| Tier | Package | Synopsis | Key Repertoire |
| :--- | :--- | :--- | :--- |
| **Tier 2A** | `gargamelle-logic` | Pure syntax ASTs, order theory, and refinement calculi | `Algebra.Lattice.Op`, `LogicAST`, `AGContract` |
| **Tier 2B** | `gargamelle-effect`| Kernmantle Arrow Rope effect orchestration layer | `VariantRouter`, profunctor optics, Coyoneda fusion |
| **Tier 3A** | `gargamelle-model` | Observable runtime models and Free VerifierAST | `ObsMor`, `VerifierAST`, `Divisible`, `Decidable` |
| **Tier 3B** | `gargamelle-evidence`| Evidence preservation and AST structural diffing | `hs-tree-sitter`, `tree-diff`, `isAstStructurallySimilar` |
| **Tier 4A** | `gargamelle-core` | Categorical institutions, pushouts, and colimits | `proarrow`, `LogicalSyntax`, `ModelTheory`, `Institution` |
| **Tier 4B** | `gargamelle-fol` | First-order logic institution & streaming Z3 SMT pipe | `FirstOrder`, `Hyperdoctrine`, `Gargamelle.FOL.Z3` |
| **Tier 4C** | `gargamelle-equational` | Equational logic institution & presheaf DPO rewriting | `Equational`, `Proarrow.Tools.DPO` |
| **Tier 4D** | `gargamelle-sandbox`| Bubblewrap container isolation and resource limits | `/usr/bin/bwrap`, `/usr/bin/timeout`, `withTempSandboxDir` |
| **Tier 4E** | `gargamelle-persistence`| Beam SQLite database persistence for runs and evidence | `beam-core`, `beam-sqlite`, `initEvidenceDb` |
| **Tier 5A** | `gargamelle-sheaf` | Cellular sheaves, Store diffusion, H¹ fault localization | `CellComplex`, `CellularSheaf`, `Store`, `coboundary` |
| **Tier 5B** | `gargamelle-workflow` | Crem Mealy state machine & sheaf-gated CEGIS loop | `crem`, `singletons-base`, `runSheafGatedCEGIS` |

---

## Quickstart & Verification

### 1. Build and Run Full Test Suite
Gargamelle builds cleanly under GHC 9.14.1 with Cabal 3.18:

```bash
# Build all packages
cabal build all

# Run the full test suite (79 examples across all 8 active test suites)
cabal test gargamelle-logic gargamelle-model gargamelle-core gargamelle-fol \
           gargamelle-equational gargamelle-sheaf gargamelle-effect gargamelle-workflow
```

### 2. Deterministic Physical Verification Harness (10 Gates)
Execute the deterministic physical verification harness exercising Bubblewrap container isolation, Beam SQLite file locking, HLint cleanliness, full test suite assertions, literate Markdown doccheck verification, mechanical Tagref cross-referencing, Markdown link integrity, Hyperlinked Haddock resolution, CLOC comment density audit, and mdBook treatise compilation:

```bash
./bin/gargamelle-verify
```

### 3. Multi-Compiler & Build System Matrix
Gargamelle supports Cabal, Stack, and Nix across GHC 9.6, 9.8, 9.10, 9.12, and 9.14. See [`docs/developer/BUILD_SYSTEMS_MATRIX.md`](docs/developer/BUILD_SYSTEMS_MATRIX.md) for full commands.

---

## Documentation Index

- [`docs/INDEX.md`](docs/INDEX.md) — Corpus inventory and reading maps.
- [`docs/textbook/src/introduction.md`](docs/textbook/src/introduction.md) — The 5-Volume Comprehensive Treatise on Categorical Institutions, Cellular Sheaves, and Sheaf-Gated CEGIS.
- [`docs/DOCUMENTATION_ROLLOUT_PLAN.md`](docs/DOCUMENTATION_ROLLOUT_PLAN.md) — Staged roll-out plan: easiest parts first for forge review, deferring treatise to co-development with sarutahiko.
- [`docs/FRAMEWORK_RECOMMENDATIONS.md`](docs/FRAMEWORK_RECOMMENDATIONS.md) — Framework recommendations: 5-volume treatise curriculum, package monographs, and literate tooling.
- [`docs/TUTORIAL.md`](docs/TUTORIAL.md) — Interactive worked tutorial from Institutions to Sheaf CEGIS.
- [`docs/NEWBIE_GUIDE.md`](docs/NEWBIE_GUIDE.md) — Repository navigation and token conservation guide.
- [`docs/MAINTAINER_GUIDE.md`](docs/MAINTAINER_GUIDE.md) — Invariants, governance, and quality gates.
- [`docs/developer/BUILD_SYSTEMS_MATRIX.md`](docs/developer/BUILD_SYSTEMS_MATRIX.md) — Cabal, Stack, and Nix matrix.
- [`docs/notes/GARGAMELLE_ARCHITECTURAL_REDESIGN.md`](docs/notes/GARGAMELLE_ARCHITECTURAL_REDESIGN.md) — Canonical v2.0 design blueprint.
- [`docs/registers/PACKAGES.md`](docs/registers/PACKAGES.md) — Complete package registry and provenance.

---

## License

Licensed under the **European Union Public Licence (EUPL-1.2)**.  
See [`LICENSE`](LICENSE) for details.