# Roadmap: gargamelle

**Status:** DRAFT · 2026-10-12  
**Project:** gargamelle (Institution framework with evidence tracking)

## Vision
Build a principled, effect‑typed infrastructure for institution‑theoretic reasoning, structural counter‑example tracking, and autonomous synthesis loops, leveraging Kernmantle for config‑time analyzable workflows, Beam for persistence, Crem for state‑machine orchestration, Liquid Haskell for formal refinement verification, and Synquid / LLM-assisted SaaS for program synthesis.

## Milestones

### M1: Kernmantle Effect Orchestration
- Define core arrow (e.g., `newtype Rope core mantle a b = Rope (Handlers mantle → core a b)`).
- Identify strands: `LogMsg`, `ReadFile`, `WriteFile`, `RunSandbox`, `QueryBeam`, `Random`, `Timer`.
- Implement handlers for each strand (production: `Kleisli IO`; test: pure mock).
- Verify config‑time analysis: build a workflow Rope and inspect its mantle without executing effects.
- **Files:** `src/Effect/Rope.hs`, `src/Effect/Strand.hs`, `src/Effect/Handlers.hs`

### M2: Beam Persistence Layer (via polytropos-beam)
- Add dependencies: `beam-core`, `beam-sqlite`, `beam-postgres`, `polytropos-beam`.
- Define `EvidenceStore` tables (evidence, counterexamples, runs).
- Lift Beam queries into Kernmantle strands (`QueryBeam`).
- Implement persistence handler using `polytropos-beam` connection pool.
- **Files:** `src/Persistence/Schema.hs`, `src/Persistence/Queries.hs`, `src/Effect/Strand/Beam.hs`

### M3: Sandbox Automation & Crem State Machine
- Model sandbox operations as Kernmantle strands (`RunSandbox`, `WithTempDir`, `WithLimits`).
- Use `kernmantle` resource bracketing to guarantee cleanup.
- Wire Crem state machine to drive the synthesis loop:
  `ProposeChange → SandboxRun → CollectEvidence → SimilarityCheck → StateTransition`.
- **Files:** `src/Sandbox/Effect.hs`, `src/Sandbox/Handler.hs`, `src/Workflow/Synthesis.hs`

### M4: Integration & Validation (including Formal Verification)
- Compose the full synthesis workflow as a Kernmantle Rope.
- Write end‑to‑end tests using `tasty` and `hedgehog`.
- Ensure config‑time analysis catches missing resources (bad DB URL, missing sandbox binary).
- Verify test interpreter returns deterministic results.
- **Optional Formal Verification via Liquid Haskell:**
  - Annotate core data structures and pure validation rules in `src/Evidence.hs` and `src/RefinementCalculus.hs` with refinement types (`{v:t | p v}`).
  - Integrate `liquid` checks into the build pipeline to verify critical invariants at compile time via SMT (Z3).
- **Files:** `test/Workflow/SynthesisSpec.hs`, `test/Persistence/SchemaSpec.hs`, refined modules in `src/`

### M5: Program Synthesis & LLM/Neural Assistance (Synquid & SaaS Integration)
- Integrate **Synquid** or type-driven synthesis components to automatically generate functions/code snippets from polymorphic refinement types.
- Combine neural networks / LLM SaaS endpoints as an advisory synthesis strand (`SuggestChanges` / `NeuralSynthesizer`) inside Kernmantle workflows.
- Use Crem state machines to guide the synthesize-verify-refine loop between neural suggestions, Liquid Haskell verification, and structural similarity checks.
- **Files:** `src/Synthesis/SynquidAdapter.hs`, `src/Synthesis/LLMClient.hs`, `src/Workflow/SynthesisLoop.hs`

### M6: Institution-Theoretic Implementations
- Implement institution (co)morphisms between core institutions (Evidence, FirstOrder, RefinementCalculus, Kernmantle, Beam, Crem).
- Develop conservative extensions/refinements to safely evolve signatures and specifications.
- Construct colimits, pushouts, and pullbacks of diagrams of institutions for gluing local specs into global correctness conditions.
- Model institution nets/graphs to represent wiring of multiple subsystems and compute propagation of changes.
- Provide functors from a time/change category to **Inst** to capture evolving specifications over successive versions or runs.
- **Files:** `src/Institution/Morphisms.hs`, `src/Institution/Extensions.hs`, `src/Institution/Limits.hs`, `src/Institution/Graph.hs`, `src/Institution/Dynamic.hs`

### M7: Documentation & Design Reviews
- Update `docs/notes/DESIGN_REVIEW_EVIDENCE.md` with Kernmantle integration.
- Add `docs/notes/DESIGN_REVIEW_WORKFLOW_EFFECTS.md` (already exists).
- Write tutorial: `docs/transcripts/KERNELMANTLE_TUTORIAL.md`.
- Ensure frequent git commits for rollback.

## Execution Mode
All milestones are `[AUTONOMOUS-MACHINE]` – the agent can implement, test, and verify without interactive human participation.

## Immediate Next Steps
1. Add Beam and Kernmantle dependencies to `gargamelle.cabal`.
2. Scaffold `src/Effect/` modules.
3. Update `cabal.project` to include local Beam and Kernmantle if needed (they are on Hackage).
4. Begin implementing strand definitions and handlers.