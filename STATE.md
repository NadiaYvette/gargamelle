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

### Phase 3: SMT Z3 Pipe & Presheaf DPO Rewriting [COMPLETED]
- **Packages**: `packages/gargamelle-fol` (`FirstOrder`, `Hyperdoctrine`, `RefinementCalculus`, `Gargamelle.FOL.Z3`), `packages/gargamelle-equational` (`Equational`, `Gargamelle.Equational.DPO`)
- **Retired Legacy ATP Submodules**: Completely removed `external/Folly` and `external/Jukebox` from `cabal.project` and package dependencies, eliminating legacy tab warnings and ancient unmaintained code.
- **Native First-Order Representation**: Replaced Folly's external term structure with native first-order terms (`Var`, `Const`, `Func`), preserving full backward compatibility across `FirstOrder`, `Hyperdoctrine`, and `RefinementCalculus`.
- **Host Z3 4.16.0 Streaming SMT Pipe**: Implemented `Gargamelle.FOL.Z3` with typed SMT-LIB2 generation, direct streaming process pipe to host Z3, model extraction into `Map String String`, and validity verification mapping tautology proofs to `VerifiedSection` and countermodels to `Counterexample`.
- **Double-Pushout (DPO) Algebraic Rewriting**: Implemented `Gargamelle.Equational.DPO` leveraging `Proarrow.Tools.DPO (Rule, dpoStep, HasPushoutComplements)`, with grounded evaluation over finite types (`FINHASK`) and algebraic equational rules, rigorously enforcing gluing conditions (refusing non-injective identification of kept and deleted elements).
- **GHC-Style Unit Test Suites**: Added 8 tests in `packages/gargamelle-fol/test/Main.hs` and 4 tests in `packages/gargamelle-equational/test/Main.hs`, 100% green.
- **Toolchain & Quality Gates**: 0 compiler warnings under GHC 9.14.1 (`-Wall`), 0 HLint hints across all 6 packages. Total test suite passes: 57 examples (0 regressions).

### Phase 4: Cellular Sheaves & Homological Fault Localization [COMPLETED]
- **Packages**: `packages/gargamelle-sheaf` (`Gargamelle.Sheaf`, `Gargamelle.Sheaf.Complex`, `Gargamelle.Sheaf.Diffusion`, `Gargamelle.Sheaf.Cohomology`)
- **Finite Cell Complexes (`CellComplex vId eId`)**: Formalized 1-dimensional graph complexes with graded cell hierarchy (`Cell0`, `Cell1`), face poset relations ($\sigma \trianglelefteq \tau$), star co-faces, boundary maps, homological incidence signs ($[e : u] = -1$, $[e : v] = +1$), and topological Euler characteristic $\chi = |V| - |E|$.
- **Cellular Sheaves (`CellularSheaf vId eId stalk edgeStalk`)**: Stalk assignments over cells, directional and symmetric restriction maps ($\rho_{u \trianglelefteq e}, \rho_{v \trianglelefteq e}$), and adjoint lifting maps.
- **Store Comonad Cellular Diffusion**: Comonadic cellular space via `Control.Comonad.Store` (`Store vId stalk`, `pos`, `extract`, `peek`), using comonadic `extend` to evaluate local neighborhood inspection rules across all vertices simultaneously.
- **Knaster-Tarski Harmonic Consensus**: Monotonic lattice diffusion (`diffuseUntilHarmonic`, `diffuseTrace`) over contract meet lattices (`Algebra.Lattice.Lattice`, `BoundedMeetSemiLattice`), proving convergence to greatest lower bounds.
- **Sheaf Coboundary Operator ($\delta^0 : C^0 \to C^1$)**: Computes boundary discrepancies $(\rho_u(x_u), \rho_v(x_v))$ along all 1-cells; detects harmonic global sections ($H^0(G; \mathcal{F}) = \ker \delta^0$) and evaluates the Model Amalgamation Theorem $H^0(G; \mathbf{Mod}) \cong \mathbf{Mod}(\operatorname{colim} D)$ over pushout diagrams.
- **Homological Fault Localization ($H^1$ Feedback)**: Cohomological obstruction maps (`locateObstructions`) pinpointing exact failing interface boundaries and mismatched contract values to directly guide CEGIS repair.
- **GHC-Style Unit Test Suite**: 9 new tests in `packages/gargamelle-sheaf/test/Main.hs`, 100% green.
- **Toolchain & Quality Gates**: 0 compiler warnings under GHC 9.14.1 (`-Wall -Werror`), 0 HLint hints across all packages. Total test suite passes: 66 examples (0 regressions).

### Phase 5: Polytropos-Kernmantle Rope & Optics [COMPLETED & UPSTREAMED]
- **Packages**: `packages/gargamelle-effect` (`Effect.Rope`, `Effect.Strand`, `Effect.Handlers`, `Effect.Strand.Beam`, `Gargamelle.Effect`, `Gargamelle.Effect.Router`, `Gargamelle.Effect.Optics`, `Gargamelle.Effect.Fusion`, `Gargamelle.Effect.Rope`)
- **Upstreamed to `polytropos`**: Created native satellite package `packages/polytropos-profunctors` in `polytropos` (commit `52f6030`), providing pure `Strong` lenses, `Choice` prisms, compile-time `FieldIndex` `fieldLens`, `ConstructorIndex` `ctorPrism`, and `typedSlotLens`/`typedVariantPrism` delegating to `Polytropos.Core.setFieldAt`.
- **Upstreamed to `kernmantle`**: Implemented `Control.Kernmantle.Rope.Variant` ($O(1)$ jump-table routing, `routeVariantWith`, and `branchRope` multi-way branching over open variants) and `Control.Kernmantle.Rope.Fusion` (Coyoneda pipeline fusion for `Rope`) on branch `polytropos-port` (commit `862b3cd`).
- **Clean Consumption in `gargamelle-effect`**: Refactored `Gargamelle.Effect.Optics`, `Gargamelle.Effect.Router`, and `Gargamelle.Effect.Fusion` to re-export and adapt upstreamed modules, eliminating redundant code while preserving 100% backward compatibility.
- **GHC-Style Unit Test Suite**: 7 new tests in `packages/gargamelle-effect/test/Main.hs`, 100% green.
- **Toolchain & Quality Gates**: 0 compiler warnings under GHC 9.14.1 (`-Wall -Werror`), 0 HLint hints across all packages. Total test suite passes: 73 examples (0 regressions).

### Phase 6: End-to-End Sheaf-Gated CEGIS Workflow [COMPLETED]
- **Packages**: `packages/gargamelle-workflow` (`Workflow.Synthesis`)
- **Sheaf-Gated Crem Mealy State Machine**: Extended Crem Mealy state machine topology with `StateSheafCheck` (`StateSimilarityCheck -> StateSheafCheck -> StateComplete`), supporting Sheaf-gated verification commands (`CmdCheckSimilarityWithSheaf`, `CmdTransitionToSheafCheck`, `CmdEvaluateSheaf`).
- **Homological Fault Localization ($H^1$ Feedback)**: Direct integration with `gargamelle-sheaf`'s coboundary operator $$\delta^0 : C^0 \to C^1$$ (`locateObstructions`). When $H^1 = 0$, confirms certified global sections ($H^0$); when boundary discrepancies occur ($H^1 \neq 0$), translates obstructions to `EvtSheafObstructionsDetected`, routing exact failing module interfaces back to `StatePropose` to guide targeted repair.
- **End-to-End Pipeline Wiring (`runSheafGatedCEGIS`)**: Fully integrates Bubblewrap container namespace isolation (`executeSandboxed`), Beam SQLite database schemas (`startRunRecord`, `completeRunRecord`, `insertEvidenceRecord`, `findEvidenceByRep`, `insertCounterexample`), and Sheaf cohomological obstruction localization into a unified pipeline.
- **Knaster-Tarski Lattice Diffusion CEGIS (`runSheafGatedCEGISWithDiffusion`)**: Integrated Store comonad cellular diffusion (`diffuseUntilHarmonic`) over contract meet semi-lattices (`Algebra.Lattice.Op`), reconciling interface discrepancies prior to reporting persistent boundary faults.
- **GHC-Style Unit & Integration Test Suite**: 6 new integration tests in `packages/gargamelle-workflow/test/Main.hs`, 100% green. Preserved 100% backward compatibility across all 20 existing workflow integration tests (26 total examples in workflow, 79 total examples across all 8 active packages, 0 failures).
- **Physical Verification Gates**: `bin/gargamelle-verify` passes all 4 physical gates (Bubblewrap isolation, SQLite file locking, clean HLint with 0 hints, all 26 test suite assertions). Zero compiler warnings under GHC 9.14.1 (`-Wall -Werror`).

### Multi-Compiler Matrix & Build System Infrastructure [COMPLETED]
- **Multi-GHC Compatibility**: GHC 9.6.7, 9.8.4, 9.10.3, 9.12.4, and 9.14.1 verified across all 11 packages.
- **Cabal**: Multi-compiler project overlays (`cabal.project.ghc-{9.6,9.8,9.10,9.12,9.14}`) importing `cabal.project` with explicit `with-compiler` directives; `tested-with` declarations added to all 11 package cabal files.
- **Stack**: Standalone configurations (`stack.yaml`, `stack-ghc-{9.6,9.8,9.10,9.12,9.14}.yaml`) referencing LTS resolvers (`lts-22.44`, `lts-23.12`) with `allow-newer` and `extra-deps`.
- **Nix**: Full declarative native build and developer shell via `default.nix`, `shell.nix` (bundling GHC, C libraries, bwrap, and z3), and `flake.nix`.
- **Documentation**: Documented in [`docs/developer/BUILD_SYSTEMS_MATRIX.md`](docs/developer/BUILD_SYSTEMS_MATRIX.md).

### Basic Documentation Suite & Expository Framework [COMPLETED]
- **README Overhaul**: Scholarly rewrite covering Rabelaisian naming provenance, plain-English motivation for institutions and cellular sheaves, tier map, 11-package register, and verification commands.
- **Core Guides**: `docs/INDEX.md`, `docs/NEWBIE_GUIDE.md`, `docs/TUTORIAL.md` (5-lesson interactive walkthrough), `docs/MAINTAINER_GUIDE.md`, and `docs/registers/PACKAGES.md`.
- **Expository & Tutorial Framework**: Authoritative specification in [`docs/FRAMEWORK_RECOMMENDATIONS.md`](docs/FRAMEWORK_RECOMMENDATIONS.md) and [`docs/notes/EXPOSITORY_AND_TUTORIAL_FRAMEWORK.md`](docs/notes/EXPOSITORY_AND_TUTORIAL_FRAMEWORK.md) specifying the 3-tier hierarchy, 5-volume treatise curriculum (`docs/textbook/`), standardized package monographs (`packages/gargamelle-*/README.md`), and literate test tooling.
- **Staged Documentation Roll-Out Plan**: Established [`docs/DOCUMENTATION_ROLLOUT_PLAN.md`](docs/DOCUMENTATION_ROLLOUT_PLAN.md), prioritizing easiest high-visibility parts first for multi-forge review (`github`, `gitcode`, `disroot`, `framagit`, `rad` with web explorer remarks). Incorporated multi-GHC (9.6–9.14) literate doc-testing, in-code GHC Notes architecture with mechanical `tagref` validation, `cloc` 50%+ comment density audit gate (in `./bin/gargamelle-verify`), and Gargamelle package cluster treatise framing with `sarutahiko` as the primary reference consumer.

## Architectural Redesign v2.0 Status: FULLY COMPLETED
All six implementation phases specified in `docs/notes/GARGAMELLE_ARCHITECTURAL_REDESIGN.md` are completely implemented, verified, and grounded:
- **Phase 1**: Substrate & Observable Verifier Core (`gargamelle-logic`, `gargamelle-model`) [COMPLETED]
- **Phase 2**: Category Core & Institutions (`gargamelle-core`) [COMPLETED]
- **Phase 3**: SMT Z3 Pipe & Presheaf DPO Rewriting (`gargamelle-fol`, `gargamelle-equational`) [COMPLETED]
- **Phase 4**: Cellular Sheaves & Homological Fault Localization (`gargamelle-sheaf`) [COMPLETED]
- **Phase 5**: Polytropos-Kernmantle Rope & Optics (`gargamelle-effect`, upstreamed to `polytropos` & `kernmantle`) [COMPLETED]
- **Phase 6**: End-to-End Sheaf-Gated CEGIS Workflow (`gargamelle-workflow`) [COMPLETED]
