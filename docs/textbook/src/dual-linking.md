# The Dual-Link Convention

To maintain complete epistemic transparency without cluttering prose or breaking offline navigation, the Gargamelle textbook adheres to a standardized **dual-link convention**.

---

## 1. The Anatomy of a Dual Link

Whenever an exported data type, typeclass, core combinator, or state machine command is introduced in textbook exposition, it is formatted as a side-by-side pair:

```markdown
[`Identifier`](<relative-source-path>) ([Hackage](<hackage-url>))
```

### Examples
- **Categorical Institution Class:**
  ``[`Institution`](../../../packages/gargamelle-core/src/Gargamelle/Core/Institution.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-core/docs/Gargamelle-Core-Institution.html#t:Institution))``
  Renders as: [`Institution`](../../../packages/gargamelle-core/src/Gargamelle/Core/Institution.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-core/docs/Gargamelle-Core-Institution.html#t:Institution))

- **Observable Morphism Arrow:**
  ``[`ObsMor`](../../../packages/gargamelle-logic/src/Gargamelle/Logic/Defunctionalize.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-logic/docs/Gargamelle-Logic-Defunctionalize.html#t:ObsMor))``
  Renders as: [`ObsMor`](../../../packages/gargamelle-logic/src/Gargamelle/Logic/Defunctionalize.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-logic/docs/Gargamelle-Logic-Defunctionalize.html#t:ObsMor))

- **Cellular Sheaf Construction:**
  ``[`CellularSheaf`](../../../packages/gargamelle-sheaf/src/Gargamelle/Sheaf.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-sheaf/docs/Gargamelle-Sheaf.html#t:CellularSheaf))``
  Renders as: [`CellularSheaf`](../../../packages/gargamelle-sheaf/src/Gargamelle/Sheaf.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-sheaf/docs/Gargamelle-Sheaf.html#t:CellularSheaf))

---

## 2. Linking Rules by Context

1. **Dual Links (Source + Hackage):** Mandatory for all publicly exported Haskell symbols. The left link points to the physical repository source line for local offline reading and git-based exploration; the right link points to published Hackage/Haddock documentation.
2. **Single Link (Source Only):** Applied to unexposed internal helper functions, private type representations, local variables, or low-level layout constants that do not appear in Hackage documentation.
3. **Single Link (External Only):** Applied to external dependencies, papers, standards, or RFCs (e.g. [Proarrow Equipment](https://hackage.haskell.org/package/proarrow), [Tree-Diff](https://hackage.haskell.org/package/tree-diff)).
4. **Mechanical Tagref Invariants:** Citations to GHC Notes use the tagref convention (e.g. [ref:note-institution-satisfaction-invariance]), which are mechanically audited by `./bin/gargamelle-tagref` during build gates to ensure zero dangling references.
