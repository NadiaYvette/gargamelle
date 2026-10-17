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

## Next Actions (Milestone M4)
- **Integration & Validation**: Compose the complete synthesis workflow as a unified Kernmantle `Rope` connecting the Crem state machine, Beam database, and Bubblewrap sandbox.
- **Property-Based Testing**: Add `hedgehog` and `tasty` generators for randomized state machine traces.
- **Formal Verification (Liquid Haskell)**: Annotate core data structures in `Evidence.hs` and `RefinementCalculus.hs` with refinement types verified via Z3.
