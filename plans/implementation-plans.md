# Implementation Plans for gargamelle Roadmap

This document provides detailed implementation plans for each milestone in the project roadmap.

## M1: Kernmantle Effect Orchestration

**Goal**: Establish the effect orchestration layer using Kernmantle to manage side effects in a configurable and analyzable way.

### Tasks
1. Define the core `Rope` type that strands effects through a mantle (handlers).
   - `newtype Rope core mantle a b = Rope (Handlers mantle -> core a b)`
   - Where `core` is the base effect (e.g., `Kleisli IO` for production, `State` for testing).
2. Identify and define the initial set of strands:
   - `LogMsg`: for logging
   - `ReadFile`: read file contents
   - `WriteFile`: write file contents
   - `RunSandbox`: execute code in a sandbox
   - `QueryBeam`: interact with the Beam persistence layer
   - `Random`: generate random values
   - `Timer`: measure time or delay
3. Implement handlers for each strand in two variants:
   - Production: using `Kleisli IO` (actual IO)
   - Test: using pure mocks (e.g., `State` or `Reader` for logging)
4. Verify config-time analysis by building a workflow `Rope` and inspecting its mantle without executing effects.
   - This ensures that missing resources (e.g., missing sandbox binary, bad DB URL) are caught at compile/config time.

### Files
- `src/Effect/Rope.hs`: Core `Rope` type and combinators.
- `src/Effect/Strand.hs`: Definitions of strands (as data types or classes).
- `src/Effect/Handlers.hs`: Type class for handling strands and instances for production and test.

### Dependencies
- Add `kernmantle` to `gargamelle.cabal`.

### Testing
- Unit tests for each strand handler in both production and test modes.
- Property tests (using `hedgehog`) for the `Rope` combinators.

## M2: Beam Persistence Layer (via polytropos-beam)

**Goal**: Integrate Beam for type-safe persistence, using the `polytropos-beam` library for connection management.

### Tasks
1. Add Beam dependencies to the project:
   - `beam-core`, `beam-sqlite`, `beam-postgres`, `polytropos-beam`
2. Define the database schema for:
   - Evidence (store `Evidence` values, similarity hashes, etc.)
   - Counterexamples (store failing cases from tests)
   - Runs (store workflow runs, timestamps, outcomes)
3. Lift Beam queries into Kernmantle strands via the `QueryBeam` strand.
   - This allows the workflow to perform database operations as an effect.
4. Implement a persistence handler for `QueryBeam` that uses a connection pool from `polytropos-beam`.

### Files
- `src/Persistence/Schema.hs`: Beam tables and entities.
- `src/Persistence/Queries.hs`: Beam queries (select, insert, update, delete).
- `src/Effect/Strand/Beam.hs`: Implementation of the `QueryBeam` strand and its handler.

### Dependencies
- Update `gargamelle.cabal` and `cabal.project` to include the Beam packages.

### Testing
- Test the schema and queries with an in-memory SQLite database.
- Use `hedgehog` to generate random database states and verify query correctness.

## M3: Sandbox Automation & Crem State Machine

**Goal**: Automate sandboxed execution and use Crem to drive the synthesis loop as a state machine.

### Tasks
1. Model sandbox operations as Kernmantle strands:
   - `RunSandbox`: execute a command in a sandbox (e.g., using `firejail` or `bubblewrap`).
   - `WithTempDir`: provide a temporary directory that is cleaned up.
   - `WithLimits`: enforce resource limits (time, memory) on sandboxed execution.
2. Use Kernmantle's resource bracketing to guarantee cleanup of temporary directories and sandbox processes.
3. Wire the Crem state machine to drive the synthesis loop:
   - States: `ProposeChange`, `SandboxRun`, `CollectEvidence`, `SimilarityCheck`, `StateTransition`
   - Transitions based on outcomes (e.g., if similarity is below threshold, transition to `ProposeChange` again).
4. Implement the Crem state machine with transitions that trigger the appropriate Kernmantle strands.

### Files
- `src/Sandbox/Effect.hs`: Sandbox-related strands.
- `src/Sandbox/Handler.hs`: Handlers for sandbox strands (using `firejail`/`bubblewrap` or similar).
- `src/Workflow/Synthesis.hs`: Crem state machine definition and integration with Kernmantle.

### Dependencies
- Ensure sandboxing tools are available (document in README).
- Add any necessary Haskell libraries for process management.

### Testing
- Test sandbox strands in isolation (using mocks for production).
- Test the Crem state machine with simulated inputs and outputs.
- Integration test: run a full synthesis loop in a test sandbox.

## M4: Integration & Validation (including Formal Verification)

**Goal**: Compose the full synthesis workflow, add end-to-end tests, and optionally integrate Liquid Haskell for formal verification.

### Tasks
1. Compose the full synthesis workflow as a Kernmantle `Rope` that includes all strands.
2. Write end-to-end tests using `tasty` and `hedgehog`:
   - Test that the workflow can start from an initial proposal and produce a validated change.
   - Test edge cases (e.g., sandbox failure, database connection failure).
3. Ensure config-time analysis catches missing resources (e.g., bad DB URL, missing sandbox binary) by inspecting the mantle of a workflow `Rope`.
4. Verify that the test interpreter returns deterministic results (given the same seed, the same outcome).
5. **Optional Formal Verification via Liquid Haskell**:
   - Annotate core data structures and pure validation rules in `src/Evidence.hs` and `src/RefinementCalculus.hs` with refinement types (`{v:t | p v}`).
   - Integrate `liquid` checks into the build pipeline (via `stack` or `cabal`).
   - Use the SMT solver (Z3) to verify critical invariants at compile time.

### Files
- `test/Workflow/SynthesisSpec.hs`: End-to-end tests for the synthesis workflow.
- `test/Persistence/SchemaSpec.hs`: Tests for the Beam schema and queries.
- Refined modules: `src/Evidence.hs`, `src/RefinementCalculus.hs` (with Liquid Haskell annotations).

### Dependencies
- Add `tasty`, `hedgehog` to the test suite.
- For Liquid Haskell: add `liquidhaskell` and ensure `z3` is installed.

### Testing
- Run the test suite with `cabal test`.
- For Liquid Haskell: run `liquid` as part of the build (e.g., in `cabal` test hook or `stack` yaml).

## M5: Program Synthesis & LLM/Neural Assistance (Synquid & SaaS Integration)

**Goal**: Integrate program synthesis components (Synquid) and neural/LLM assistance as advisory strands in the Kernmantle workflow.

### Tasks
1. Integrate **Synquid** (or a similar type-driven synthesis tool) to generate functions/code snippets from polymorphic refinement types.
   - Create an adapter that takes a type signature and refinement constraints and returns synthesized code.
2. Combine neural networks / LLM SaaS endpoints as an advisory synthesis strand:
   - `SuggestChanges`: propose changes based on neural network models.
   - `NeuralSynthesizer`: generate code snippets from an LLM API (e.g., OpenAI, local LLM).
3. Use Crem state machines to guide the synthesize-verify-refine loop:
   - The loop involves: neural suggestion → Liquid Haskell verification → structural similarity check → (if passes) accept, else refine.
   - The Crem state machine manages the state transitions based on the outcomes of each step.
4. Implement the synthesis loop as a Kernmantle workflow that can be configured to use different synthesis strategies.

### Files
- `src/Synthesis/SynquidAdapter.hs`: Adapter for Synquid.
- `src/Synthesis/LLMClient.hs`: Client for LLM SaaS endpoints (with API key management).
- `src/Workflow/SynthesisLoop.hs`: Crem state machine and Kernmantle composition for the synthesize-verify-refine loop.

### Dependencies
- Install Synquid (if available) or link to its repository.
- For LLM SaaS: add HTTP client libraries (e.g., `http-conduit`, `aeson`).
- Ensure API keys are managed securely (via environment variables or a vault).

### Testing
- Unit tests for the Synquid adapter (using known synthesis problems).
- Mock tests for the LLM client (to avoid real API calls during testing).
- Property tests for the synthesis loop (using `hedgehog` to generate initial states and verify loop termination).

## M6: Institution-Theoretic Implementations

**Goal**: Implement the institution-theoretic concepts (co)morphisms, extensions, limits, etc., to support modular reasoning and change propagation.

### Tasks
1. Implement institution (co)morphisms between core institutions:
   - Evidence institution (signatures: evidence fields; sentences: refinement predicates; models: evidence values)
   - FirstOrder institution (plain first-order logic)
   - RefinementCalculus institution (refinement types)
   - Kernmantle institution (effects and strands)
   - Beam institution (database tables and queries)
   - Crem institution (state machines and transitions)
   - Each comorphism includes signature translation, sentence translation (contravariant), and model translation (covariant).
2. Develop conservative extensions/refinements:
   - Allow safe evolution of signatures (adding new symbols) and specifications (adding new sentences) while preserving existing theorems.
   - Implement model expansions to show conservativity.
3. Construct colimits, pushouts, and pullbacks of diagrams of institutions:
   - Use colimits to glue local specifications from multiple institutions into a global correctness condition.
   - Use pushouts to identify institutions along a comorphism (e.g., when linking two modules).
   - Use pullbacks to find the greatest common sub-institution.
4. Model institution nets/graphs:
   - Represent the wiring of multiple subsystems as a graph of institutions connected by comorphisms.
   - Implement algorithms to compute the propagation of changes (e.g., when a specification is strengthened, recompute the global institution).
5. Provide functors from a time/change category to **Inst**:
   - Capture evolving specifications over successive versions or runs.
   - Allow the system to adapt its specification over time while maintaining a record of changes.

### Files
- `src/Institution/Morphisms.hs`: Institution (co)morphisms and their properties.
- `src/Institution/Extensions.hs`: Conservative extensions and refinements.
- `src/Institution/Limits.hs`: Colimits, pushouts, pullbacks of institution diagrams.
- `src/Institution/Graph.hs`: Institution nets/graphs and change propagation algorithms.
- `src/Institution/Dynamic.hs`: Functors from a time/change category to **Inst** for evolving specifications.

### Dependencies
- Ensure the project has a solid foundation in category theory (we can use `adjunctions`, `kan-extensions`, or similar if needed, but we will implement the core concepts directly).
- No major external dependencies beyond the standard library and possibly `containers` for graphs.

### Testing
- Unit tests for each institution (co)morphism (e.g., verify satisfaction preservation).
- Property tests for conservative extensions (generate random extensions and check that old theorems still hold).
- Tests for colimit constructions (verify that the universal property holds).
- Tests for graph algorithms (e.g., change propagation correctness).

## M7: Documentation & Design Reviews

**Goal**: Produce comprehensive documentation and design reviews to support understanding and maintenance.

### Tasks
1. Update `docs/notes/DESIGN_REVIEW_EVIDENCE.md` to reflect the Kernmantle integration (how Evidence is used as an institution and linked to other strands).
2. Ensure `docs/notes/DESIGN_REVIEW_WORKFLOW_EFFECTS.md` exists (it does from earlier work) and update if needed.
3. Write a tutorial: `docs/transcripts/KERNELMANTLE_TUTORIAL.md` that explains:
   - How to define strands and handlers.
   - How to compose a workflow `Rope`.
   - How to test with mock handlers.
   - How to enable config-time analysis.
4. Ensure frequent git commits for rollback (already a practice, but emphasize in documentation).
5. Update any other design notes as needed (e.g., for Beam, Crem, Institution theory).

### Files
- `docs/notes/DESIGN_REVIEW_EVIDENCE.md`
- `docs/notes/DESIGN_REVIEW_WORKFLOW_EFFECTS.md` (update if needed)
- `docs/transcripts/KERNELMANTLE_TUTORIAL.md`

### Dependencies
- No additional code dependencies, but ensure documentation tools are available (we are just writing Markdown).

### Testing
- Documentation is validated by readability and completeness; no automated tests, but we can check for broken links or missing sections.

## Execution Mode

## Code Quality Checks

To maintain a high standard of code quality, we enforce the following checks:

1. **GHC warnings**: Build with `-Wall` (and optionally `-Werror`) to ensure no warnings.
2. **HLint**: Run `hlint .` and ensure no hints remain (or fix them).
   - Use the custom hint files from `~/src/polytropos/.hlint.yaml` if available.
3. **Stan**: Run Stan (the Haskell linter) with rules from `~/src/polytropos/rules/stan/` and ensure warning clean.
4. **Brittany**: Format code with Brittany and ensure the formatted code matches the source (i.e., no diff).
   - Use the config file `~/src/polytropos/.brittany` if present.
5. **Haddock**: Generate documentation with `cabal haddock` and ensure no warnings (except possibly about GHC internals).
6. **Liquid Haskell** (optional but recommended): Run `liquid` to verify refinement types;
   - Use the liquid configuration from `~/src/polytropos/liquid/` if available.

These checks should be run as part of the continuous integration (or local development) pipeline.
Before starting a milestone, ensure the codebase passes all checks.


All milestones are `[AUTONOMOUS-MACHINE]` – the agent can implement, test, and verify without interactive human participation.

## Immediate Next Steps

1. Add Beam and Kernmantle dependencies to `gargamelle.cabal`.
2. Scaffold `src/Effect/` modules (M1).
3. Update `cabal.project` to include local Beam and Kernmantle if needed (they are on Hackage).
4. Begin implementing strand definitions and handlers (M1).