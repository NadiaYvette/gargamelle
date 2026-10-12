# Transcript: Discussion on Institutions (2026-10-12)

**User Question:**
What do institutions represent? Is it something like a module that they represent? There are concepts like interfaces from OOP, modules (most languages have something but of varying strengths; OCaml may have the strongest), libraries (like ELF DSOs or .so files), and there can be higher levels of hierarchy in the groupings though to the extent there are standardised names, the referents or definitions vary, like a git repo can have a varying number of levels of hierarchy between it and the more standardised concepts of libraries, packages are bolted to effective equivalence with libraries in Haskell but may not be in all languages or contexts, etc. But there's a fair amount of potential structure just within the cases of linked code, where IPC and RPC raise the spectre of still higher levels of hierarchy in the structure and a largely distinct topology from what arises via linking. Or am I thinking of how to apply institutions to real code etc. wrongly? I can see glints of a notion that institutions could simply absorb larger-scale structure, but that seems as if it would be uninformative beside ways to understand structures aggregating many institutions that maintain understandings of interactions between institutions. What theory and literature is there for understanding these sorts of ideas about institutions? Is something already there for this within the sheaf-theoretic framework that I just didn't understand?

**Assistant Response:**
Institutions are not a direct syntactic artefact like a Haskell module or an OCaml functor; they are an abstract, logical-level notion that captures the syntax-semantics of a formal system in a way that makes it easy to talk about modularity, translation, and combination of different logical frameworks (first-order, equational, higher-order, modal, temporal, refinement-type, etc.). 

An institution 𝕀 = ⟨Sig, Sen, Mod, ⊧⟩ consists of:
- **Sig**: signatures (the symbols you may write; think export lists, type‑class signatures, or RPC interfaces).
- **Sen**: sentences over a signature (specifications, axioms, refinement predicates, test properties).
- **Mod**: models that interpret a signature (implementations, algebras, transition systems, concrete values).
- **⊧**: satisfaction relation telling which models make which sentences true (type checking, proving, model‑checking, testing, SMT solving, …).

This abstraction lets us treat a module or library as an institution, and linking two modules as an institution (co)morphism that translates signatures, sentences and models while preserving satisfaction. 

Institutions behave like sheaves over the category of signatures; the sheaf condition formalises how local specifications can be glued into a global one. 

Key references include:
- Goguen & Burstall 1984 “Institutions: Abstract Model Theory for Specification and Programming”.
- Tarlecki (various) on institution morphisms, conservative extensions, and refinement.
- Diaconescu 1999 “Institutions as sheaves”.
- Meseguer 1989 “General Logics”.
- Recent work on dynamic institutions, institution nets/graphs, and functors from a time/change category to **Inst** for evolving specifications.

In the context of the *programming‑in‑the‑large* project, each subsystem (Evidence, FirstOrder, Kernmantle strands, Beam persistence, Crem state machine) can be seen as an institution.  Comorphisms between them express translations (e.g., from refinement‑type specifications to plain first‑order for SMT checking, or from Evidence observations to Kernmantle effect specifications).  The global specification of the system is the colimit of the diagram of these comorphisms; changes to a subsystem propagate via the universal property of the colimit, and the sheaf condition ensures compatibility of local specifications.

The roadmap has been updated to include concrete implementation of:
- institution (co)morphisms,
- conservative extensions/refinements,
- colimits, pushouts, pullbacks of diagrams of institutions,
- institution nets/graphs,
- functors from a time/change category to **Inst**.

All changes have been committed and the project builds successfully.
