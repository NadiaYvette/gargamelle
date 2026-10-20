# docs/INDEX.md — Corpus Inventory and Reading Map

**Status:** LIVING DOCUMENT · v2.0 · 2026-10-20  
**Parent Strategy:** [`notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md)  

---

## Part 1 — Inventory

| Path | Genre | Stage | Tier | Flags |
| :--- | :--- | :--- | :--- | :--- |
| `README.md` | orientation | live | cross-cutting | Root architectural overview, 11-package suite, Rabelaisian naming, and quickstart |
| `NEWBIE_GUIDE.md` | guide | live | cross-cutting | Progressive disclosure funnel, package navigation, and token conservation |
| `TUTORIAL.md` | tutorial | live | cross-cutting | 5-lesson hands-on walkthrough: ObsMor, Institutions, Z3, Sheaves, and Crem CEGIS |
| `MAINTAINER_GUIDE.md` | guide | live | cross-cutting | Governance, observability doctrine, 4 physical verification gates, and commit trailers |
| `developer/BUILD_SYSTEMS_MATRIX.md`| guide | live | cross-cutting | Multi-compiler matrix (GHC 9.6–9.14) across Cabal, Stack, and Nix |
| `FRAMEWORK_RECOMMENDATIONS.md`| specification | live | cross-cutting | Recommendations for 5-volume textbook curriculum, package monographs, and literate tooling |
| `notes/GARGAMELLE_ARCHITECTURAL_REDESIGN.md`| design | blessed | cross-cutting | Canonical v2.0 blueprint: 6 implementation phases, 11 packages, Hackage repertoire |
| `notes/EXPOSITORY_AND_TUTORIAL_FRAMEWORK.md`| proposal| blessed | cross-cutting | Detailed framework specification, chapter syllabi, and literate tooling |
| `notes/CATEGORICAL_FOUNDATIONS_SURVEY.md`| notes | live | cross-cutting | Comprehensive survey of higher categories, proarrow, cellular sheaves, and observability |
| `notes/HASK2_UNSATURATED_TYPE_FAMILIES.md`| notes | live | cross-cutting | Resolves the folklore Hask2 2-category obstacle via Proarrow equipments and ObsMor |
| `notes/DOC_STRATEGY.md` | strategy | blessed | cross-cutting | Documentation lifecycle, genre definitions, canonicity, and the §4 precedence rule |
| `notes/COMMIT_ATTRIBUTION.md` | convention | blessed | cross-cutting | Linux kernel RFC 2822 trailer format and AI attribution guidelines |
| `notes/PROVENANCE.md` | convention | blessed | cross-cutting | Project lineage and licensing obligations |
| `registers/PACKAGES.md` | register | live | cross-cutting | Exhaustive register of all 11 packages in `packages/`, tiers, and module exports |
| `registers/THIRD_PARTY.md` | register | live | cross-cutting | Third-party dependency licenses and attribution register |
| `tools/MODERNIZER_AND_LINTER_GUIDE.md` | guide | live | cross-cutting | HLint rules, Retrie rewrites, and code modernization tooling |
| `tools/FORMAL_VERIFICATION_AND_SYNTHESIS_GUIDE.md`| guide | live | cross-cutting | LiquidHaskell, Synquid synthesis, and SMT integration |
| `tools/SOURCE_FORMATTERS_AND_LAYOUT_GUIDE.md` | guide | live | cross-cutting | Fourmolu, Ormolu, Brittany, and Floskell formatters |
| `transcripts/gemini-modelling-institutions.md` | transcript | archive | cross-cutting | Ideation dialogue: institutions, pushout weaving, and ATP replacement |
| `transcripts/gemini-advanced-functional-programming.md`| transcript | archive | cross-cutting | 7-layer functional programming blueprint: sheaves, repertoire, and observability |
| `transcripts/google-search-category-theory.md` | transcript | archive | cross-cutting | Higher categories, n-ary arrows, and peeling conjugation |
| `transcripts/FIRSTORDER_TUTORIAL.md` | transcript | live | cross-cutting | First-order logic and hyperdoctrine background |

---

## Part 2 — Reading Paths

1. **Newcomer to Gargamelle:**  
   `README.md` → `NEWBIE_GUIDE.md` → `TUTORIAL.md` (5-lesson interactive walkthrough) → `notes/GARGAMELLE_ARCHITECTURAL_REDESIGN.md`.

2. **Maintainer & Release Lead:**  
   `MAINTAINER_GUIDE.md` → `developer/BUILD_SYSTEMS_MATRIX.md` → `registers/PACKAGES.md` → `notes/DOC_STRATEGY.md`.

3. **Logician & Category Theorist:**  
   `notes/CATEGORICAL_FOUNDATIONS_SURVEY.md` → `notes/HASK2_UNSATURATED_TYPE_FAMILIES.md` → `packages/gargamelle-core` (`Institution.hs`, `Weaving.hs`, `Colimit.hs`) → `packages/gargamelle-sheaf` (`Diffusion.hs`, `Cohomology.hs`).

4. **Synthesis & Verification Engineer:**  
   `packages/gargamelle-workflow` (`Workflow.Synthesis.hs`) → `packages/gargamelle-fol` (`Gargamelle.FOL.Z3.hs`) → `packages/gargamelle-sandbox` (`Sandbox.Handler.hs`) → `packages/gargamelle-persistence` (`Persistence.Beam.hs`).

5. **AI Coding Assistant:**  
   `AGENTS.md` (bounded ~4 KB orientation projection) → `NEWBIE_GUIDE.md` (progressive disclosure funnel) → `notes/GARGAMELLE_ARCHITECTURAL_REDESIGN.md`.

6. **Anyone Modifying Documentation:**  
   `notes/DOC_STRATEGY.md` (precedence rule §4: code wins at runtime; notes corrected regardless).

7. **Authoring Expository & Tutorial Materials:**  
   `FRAMEWORK_RECOMMENDATIONS.md` → `notes/EXPOSITORY_AND_TUTORIAL_FRAMEWORK.md` → `TUTORIAL.md` → `notes/DOC_STRATEGY.md`.
