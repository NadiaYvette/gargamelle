# Chapter 3: The Store Comonad on Cell Complexes

**Volume III:** Applied Algebraic Topology & Cellular Sheaves  
**GHC Note Invariant:** Note [Store Comonad Cellular Diffusion and Harmonic Consensus] [ref:note-store-comonad-diffusion]  
**Production Module:** [`Gargamelle.Sheaf.Diffusion`](../../../../packages/gargamelle-sheaf/src/Gargamelle/Sheaf/Diffusion.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-sheaf/docs/Gargamelle-Sheaf-Diffusion.html))

---

## 1. Cellular Space as a Comonad

While monads model effectful computation and state modification, **comonads model context-dependent observation**. Specifically, `Control.Comonad.Store (Store s a)` represents a spatial configuration with a current focused position `pos :: s` and an environment lookup function `peek :: s -> a`.

When $s = V$ (the set of vertices in our cell complex), `Store vId stalk` formalizes a cellular space where each component observes its immediate neighborhood.

---

## 2. Simultaneous Cellular Diffusion via `extend`

Using comonadic `extend`, a local cellular update rule that inspects the focused vertex and its incident co-faces can be applied across all vertices simultaneously:

```haskell:ignore
diffuseStep :: (Ord vId) => (Store vId stalk -> stalk) -> Store vId stalk -> Store vId stalk
diffuseStep localRule space = extend localRule space
```

As detailed in Note [Store Comonad Cellular Diffusion and Harmonic Consensus] [ref:note-store-comonad-diffusion], this comonadic formulation guarantees that information propagates along interface boundaries without race conditions or scheduling artifacts.
