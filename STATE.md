# gargamelle — State

Operational frontier. Read with `plans/2026-10-12-full-completion-roadmap.md`; update before ending a session.

## Where we are

The modular multi-package restructuring into 8 first-class Cabal packages (`packages/gargamelle-*`) is complete and fully grounded.
Milestones M1, M2, and M3 are implemented, isolated into their respective functional packages, and verified through deterministic in-process gates.
All packages build cleanly under GHC 9.10.3 (`cabal build all`), HLint reports 0 hints across all packages (under both default and Polytropos custom rules), and the full test suite (`cabal test gargamelle-workflow:test:tests`) passes cleanly with 20 examples, 0 failures, and 0 compiler warnings.

### Package Architecture
- **`gargamelle-core`**: Core `Institution` typeclass, `Propositional`, `SessionTypes`, `Sheaf`, `CEGIS`, and `Core.AST`. Pure logic specifications without heavy external dependencies.
- **`gargamelle-fol`**: First-Order Logic institution interfacing with `Folly`, including `Hyperdoctrine` and `RefinementCalculus`.
- **`gargamelle-equational`**: Equational logic institution interfacing with `Jukebox`.
- **`gargamelle-evidence`**: Evidence preservation, tree-sitter AST parsing (`hs-tree-sitter`), and structural diffing (`tree-diff`).
- **`gargamelle-effect`**: Kernmantle Arrow `Rope` effect orchestration layer with `Strand`, `Handlers`, and static config-time analysis (Milestone M1).
- **`gargamelle-persistence`**: Beam SQLite database schemas, queries, and on-disk persistent storage (Milestone M2).
- **`gargamelle-sandbox`**: Bubblewrap namespace sandboxing, resource limit enforcement, and isolated directory bracketing (Milestone M3).
- **`gargamelle-workflow`**: Autonomous synthesis loop, Crem state machine orchestration, and end-to-end integration test runner (Milestone M3/M4).

### Milestone M1: Kernmantle Effect Orchestration [COMPLETED]
- **Package**: `packages/gargamelle-effect` (`Effect.Rope`, `Effect.Strand`, `Effect.Handlers`, `Effect.Strand.Beam`)
- **Core Arrow**: `newtype Rope core mantle a b = Rope (Handlers core -> core a b)` with `Category`, `Arrow`, and `ArrowChoice` instances.
- **Strands**: `LogMsg`, `ReadFile`, `WriteFile`, `RunSandbox`, `QueryBeam`, `Random`, `Timer`.
- **Interpreters**: Production IO (`Kleisli IO`), Pure mock (`Kleisli (Either Text)`), and Beam SQLite handlers.
- **Static Config-Time Analysis**: `Requirements` mantle inspection without executing side-effects, plus physical environment resource verification (`validateWorkflowResources`) catching missing sandbox binaries and DB paths prior to execution.

### Milestone M2: Beam Persistence Layer [COMPLETED]
- **Package**: `packages/gargamelle-persistence` (`Persistence.Schema`, `Persistence.Queries`, `Persistence.Beam`)
- **Tables**: `EvidenceRecordT`, `CounterexampleRecordT`, and `RunRecordT` with derived primary keys.
- **Operations**: `initEvidenceDb`, `insertEvidenceRecord`, `findEvidenceByRep`, `insertCounterexample`, `findCounterexamplesFor`, `startRunRecord`, `completeRunRecord`.
- **Grounded Persistence**: Verified against in-memory SQLite and physical on-disk SQLite databases (`.sqlite` files across connection lifecycles).

### Milestone M3: Sandbox Automation & Crem State Machine [COMPLETED]
- **Packages**: `packages/gargamelle-sandbox` (`Sandbox.Effect`, `Sandbox.Handler`), `packages/gargamelle-workflow` (`Workflow.Synthesis`)
- **Physical Sandboxing**: Linux container namespace isolation via Bubblewrap (`/usr/bin/bwrap`) with `/usr/bin/timeout` enforcement and isolated directory bind-mounting.
- **Resource Limits**: `ResourceLimits` (default 30s timeout, 1024 MB RAM).
- **Crem State Machine**: Formally verified Mealy state machine topology:
  `StatePropose -> StateSandboxRun -> StateCollectEvidence -> StateSimilarityCheck -> StateComplete/Retry`.
- **AST Structural Similarity**: Grounded tree diffing via `Data.TreeDiff` (`computeExprSimilarity`, `computeTreeDiffSimilarity`, `isAstStructurallySimilar`).

### Code Quality & Static Analysis Gates [COMPLETED]
- **HLint Cleanliness**: Both default HLint rules and `/home/nyc/src/polytropos/.hlint.yaml` report 0 hints across all packages in `packages/gargamelle-*/src`.
- **SMT Solver**: Z3 4.16.0 active on host.
- **Harness & Verification Scripts**:
  - `bin/gargamelle-verify`: CLI supporting `--all`, `--sandbox`, `--beam`, `--hlint`, `--tests`.
  - `scripts/tasks/verify-milestones.sh`: Deterministic verification gate script.

### Phase 1: Substrate & Observable Verifier Core [COMPLETED]
- **Packages**: `packages/gargamelle-logic`, `packages/gargamelle-model`
- **Observable Morphisms (`ObsMor a b`)**: Reified AST replacing opaque `(->)` closures, with `Category`, `Profunctor`, `Strong`, and `Choice` instances. Fully introspectable via `inspectObsMor` without execution.
- **Free Verifier AST (`Verifier model`)**: First-order `Divisible` and `Decidable` tree (`AtomCheck`, `DivideV`, `ChooseV`, `ConquerV`, `LoseV`, `ContramapV`). Evaluates against models returning `Evidence` (`VerifiedSection` or accumulated `Counterexample`). Introspectable via `inspectVerifierPlan`.
- **Dual Assume-Guarantee Contracts (`AGContract a g`)**: Powered by `Algebra.Lattice.Op`. Refinement meet (`/\`) weakens assumptions (joins in base lattice) while strengthening guarantees (meets in base lattice). Bound laws verified, circular soundness checked via `verifyCircularAG`.
- **Galois Connections (`Galois arr v e`)**: Parameterized over arrow category `arr` (`ObsMor`), supporting serial composition via `composeGalois`.
- **First-Order Logic AST (`LogicAST sig`)**: Kind-indexed deep formula AST with atomic predicates, standard connectives, and flat conjunction/disjunction nodes.
- **GHC-Style Unit Test Suite**: 17 new tests (8 in `gargamelle-logic:test:tests`, 9 in `gargamelle-model:test:tests`), 100% green.
- **Toolchain & Quality Gates**: 0 compiler warnings under GHC 9.14.1 (`-Wall`), 0 HLint hints across both new packages. Total test suite passes: 37 examples, 0 failures.

### Phase 2: Category Core & Institutions [COMPLETED]
- **Packages**: `packages/gargamelle-core` (`Gargamelle.Core.Institution`, `Gargamelle.Core.Weaving`, `Gargamelle.Core.Discovery`, `Gargamelle.Core.Colimit`)
- **Proarrow Category Integration**: Vendored and linked `proarrow` and `proarrow-equipment` into `cabal.project`, fully verified under GHC 9.14.1.
- **Categorical Institutions**: Kind-indexed signatures (`type Sig i :: Type`), covariant sentence translation (`translateSen`), contravariant model reduction via observable morphisms (`reductMod`), and Goguen-Burstall satisfaction condition verification (`satisfactionVerifier` emitting inspectable Free `Verifier` ASTs).
- **Institution Comorphisms**: Stepwise refinement passes parameterized by defunctionalized type-level signature translations (`InstitutionComorphism`).
- **Pushout Feature Weaving ($B \amalg_C W$)**: Non-invasive feature composition combining base logic $B$ and aspect $W$ over shared interface $C$, with model amalgamation (`PushoutWeaving`, `weaveAspect`, `AmalgamatedModel`).
- **Pullback Protocol Discovery ($A \times_E B$)**: Protocol and interface discovery and candidate factorization (`discoverInterface`, `factorInterface`).
- **Colimit Change Propagation**: Cocones and mediating semantic delta factorizers (`factorSemanticDelta`).
- **Backward Compatibility**: `Institution.hs` re-exports both legacy types (`Institution`, `Propositional`, `SessionTypes`, `Sheaf`) and modern categorical interfaces.
- **GHC-Style Unit Test Suite**: 8 dedicated tests in `packages/gargamelle-core/test/Main.hs`, 100% green.
- **Toolchain & Quality Gates**: 0 compiler warnings under GHC 9.14.1 (`-Wall`), 0 HLint hints across all packages. Total test suite passes: 45 examples across logic, model, core, and workflow (0 regressions).

## Next Actions (v2.0 Architectural Redesign: Phase 3)
- **Phase 3: SMT Z3 Pipe & Presheaf DPO Rewriting**:
  - Retire legacy `external/Folly` and `external/Jukebox` dependencies from active build plan.
  - Implement direct typed Z3 SMT solver pipe in `gargamelle-logic` or `gargamelle-fol` using modern SMTLIB2 / Z3 CLI interaction.
  - Implement double-pushout (DPO) rule transformation and presheaf rewriting using `Proarrow.Tools.DPO`.
- **Phase 4: Cellular Sheaves & Homological Fault Localization**: Implement `gargamelle-sheaf` Store cellular automaton and $H^1$ obstruction feedback.
- **Phase 5: Polytropos-Kernmantle Rope & Optics**: Port `gargamelle-effect` to Polytropos $O(1)$ variant jump tables (`deriveRouter`) and Coyoneda array fusion.
- **Phase 6: End-to-End Sheaf-Gated CEGIS Workflow**: Bind $H^1$ coboundaries into Crem Mealy state machines and Kernmantle `Rope` arrows, preserving the 20 existing passing integration tests.

