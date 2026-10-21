# Chapter 2: Cellular Sheaves & Stalk Assignments

**Volume III:** Applied Algebraic Topology & Cellular Sheaves  
**GHC Note Invariant:** Note [Cellular Sheaf Restriction Maps and Stalk Functors] [ref:note-cellular-sheaf-stalks]  
**Production Type:** [`CellularSheaf`](../../../../packages/gargamelle-sheaf/src/Gargamelle/Sheaf.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-sheaf/docs/Gargamelle-Sheaf.html#t:CellularSheaf))

---

## 1. Functorial Stalks & Restriction Maps

A cellular sheaf $\mathcal{F}$ over a cell complex $G$ is a functor from the face poset $(\mathrm{Cell}(G), \trianglelefteq)$ to a category of data values:
1. To each 0-cell $v \in V$, it assigns a **vertex stalk** $\mathcal{F}(v)$ representing local component state or contract guarantees.
2. To each 1-cell $e \in E$, it assigns an **edge stalk** $\mathcal{F}(e)$ representing interface channel constraints.
3. For each incidence $v \trianglelefteq e$, it assigns a **restriction map** $\rho_{v \trianglelefteq e} : \mathcal{F}(v) \to \mathcal{F}(e)$ projecting component states onto the shared interface.

---

## 2. Haskell Definition

In [`gargamelle-sheaf`](../../../../packages/gargamelle-sheaf/README.md) ([Hackage](https://hackage.haskell.org/package/gargamelle-sheaf)), a cellular sheaf is constructed via [`CellularSheaf`](../../../../packages/gargamelle-sheaf/src/Gargamelle/Sheaf.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-sheaf/docs/Gargamelle-Sheaf.html#t:CellularSheaf)):

```haskell:ignore
data CellularSheaf vId eId stalk edgeStalk = CellularSheaf
  { csComplex      :: CellComplex vId eId
  , csVertexStalks :: Map vId stalk
  , csEdgeStalks   :: Map eId edgeStalk
  , csRestrictionU :: Map eId (stalk -> edgeStalk)
  , csRestrictionV :: Map eId (stalk -> edgeStalk)
  }
```

As formalized in Note [Cellular Sheaf Restriction Maps and Stalk Functors] [ref:note-cellular-sheaf-stalks], directional restriction maps project internal component contracts onto boundary interfaces, enabling the detection of boundary mismatches without exposing private implementation state.
