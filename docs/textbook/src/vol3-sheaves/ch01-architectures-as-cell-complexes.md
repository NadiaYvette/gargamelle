# Chapter 1: Software Architectures as Cell Complexes

**Volume III:** Applied Algebraic Topology & Cellular Sheaves  
**Production Type:** [`CellComplex`](../../../../packages/gargamelle-sheaf/src/Gargamelle/Sheaf/Complex.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-sheaf/docs/Gargamelle-Sheaf-Complex.html#t:CellComplex))

---

## 1. Topologizing Architecture

Graph theory models components as nodes and interactions as edges. However, standard graph theory lacks the graded algebraic machinery (chains, cochains, boundaries, coboundaries) necessary to compute topological obstructions.

Gargamelle formalizes software architecture as a **1-Dimensional Cell Complex** $G = (V, E)$:
- **0-Cells ($V$):** Graded 0-dimensional components (individual modules, actors, or microservices).
- **1-Cells ($E$):** Graded 1-dimensional interface boundaries connecting adjacent components.
- **Incidence Signs ($[e : v]$):** Directional orientation signs where $[e : u] = -1$ (source/tail) and $[e : v] = +1$ (target/head).
- **Euler Characteristic ($\chi$):** Topological invariant $\chi = |V| - |E|$ measuring global connectivity.

---

## 2. Haskell Implementation in `gargamelle-sheaf`

The [`CellComplex`](../../../../packages/gargamelle-sheaf/src/Gargamelle/Sheaf/Complex.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-sheaf/docs/Gargamelle-Sheaf-Complex.html#t:CellComplex)) data type models this structure with efficient `Map` lookups:

```haskell:ignore
data CellComplex vId eId = CellComplex
  { ccVertices :: Set vId
  , ccEdges    :: Map eId (vId, vId)
  } deriving (Eq, Show, Generic)
```

Functions such as [`starCoFaces`](../../../../packages/gargamelle-sheaf/src/Gargamelle/Sheaf/Complex.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-sheaf/docs/Gargamelle-Sheaf-Complex.html#v:starCoFaces)) identify all 1-cells incident to a given 0-cell, forming the basis for local neighborhood inspection.
