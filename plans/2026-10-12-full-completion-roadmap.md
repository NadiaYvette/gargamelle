# Roadmap: programming-in-the-large

**Status:** DRAFT · 2026-10-12  
**Project:** programming-in-the-large (Institution framework with evidence tracking)

## Vision
Build a principled, effect‑typed infrastructure for institution‑theoretic reasoning, structural counter‑example tracking, and autonomous synthesis loops, leveraging Kernmantle for config‑time analyzable workflows, Beam for persistence, and Crem for state‑machine orchestration.

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

### M4: Integration & Validation
- Compose the full synthesis workflow as a Kernmantle Rope.
- Write end‑to‑end tests using `tasty` and `hedgehog`.
- Ensure config‑time analysis catches missing resources (bad DB URL, missing sandbox binary).
- Verify test interpreter returns deterministic results.
- **Files:** `test/Workflow/SynthesisSpec.hs`, `test/Persistence/SchemaSpec.hs`

### M5: Documentation & Design Reviews
- Update `docs/notes/DESIGN_REVIEW_EVIDENCE.md` with Kernmantle integration.
- Add `docs/notes/DESIGN_REVIEW_WORKFLOW_EFFECTS.md` (already exists).
- Write tutorial: `docs/transcripts/KERNELMANTLE_TUTORIAL.md`.
- Ensure frequent git commits for rollback.

## Execution Mode
All milestones are `[AUTONOMOUS-MACHINE]` – the agent can implement, test, and verify without interactive human participation.

## Immediate Next Steps
1. Add Beam and Kernmantle dependencies to `programming-in-the-large.cabal`.
2. Scaffold `src/Effect/` modules.
3. Update `cabal.project` to include local Beam and Kernmantle if needed (they are on Hackage).
4. Begin implementing strand definitions and handlers.