# Chapter 4: Institution Comorphisms

**Volume I:** Abstract Model Theory & Categorical Institutions  
**Production Type:** [`InstitutionComorphism`](../../../../packages/gargamelle-core/src/Gargamelle/Core/Institution.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-core/docs/Gargamelle-Core-Institution.html#t:InstitutionComorphism))

---

## 1. Mapping Between Logics

While signature morphisms translate vocabulary *within* a single institution, **institution comorphisms** map between completely different institutions:

$$\rho = (\Phi, \alpha, \beta) : \mathcal{I} \to \mathcal{J}$$

Where:
- $\Phi : \mathbf{Sign}_{\mathcal{I}} \to \mathbf{Sign}_{\mathcal{J}}$ maps source signatures to target signatures.
- $\alpha : \mathbf{Sen}_{\mathcal{I}} \Rightarrow \mathbf{Sen}_{\mathcal{J}} \circ \Phi$ maps source sentences to target sentences.
- $\beta : \mathbf{Mod}_{\mathcal{J}} \circ \Phi^{\mathrm{op}} \Rightarrow \mathbf{Mod}_{\mathcal{I}}$ reduces target models back to source models.

---

## 2. Stepwise Compilation & SMT Lowering

In Gargamelle, institution comorphisms represent stepwise compilation and lowering passes. For instance, lowering a high-level contract specification in `gargamelle-logic` into first-order clauses in `gargamelle-fol` is formalized as an [`InstitutionComorphism`](../../../../packages/gargamelle-core/src/Gargamelle/Core/Institution.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-core/docs/Gargamelle-Core-Institution.html#t:InstitutionComorphism)).

The comorphism condition guarantees that whenever the lowered formula is valid in the target logic, the original high-level contract holds in the source program.
