# Chapter 4: Knaster-Tarski Consensus Diffusion

**Volume III:** Applied Algebraic Topology & Cellular Sheaves  
**Production Function:** [`diffuseUntilHarmonic`](../../../../packages/gargamelle-sheaf/src/Gargamelle/Sheaf/Diffusion.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-sheaf/docs/Gargamelle-Sheaf-Diffusion.html#v:diffuseUntilHarmonic))

---

## 1. Monotonic Contraction on Meet Semi-Lattices

When distributed components exchange contract updates, naive message-passing frequently diverges into oscillatory cycles. 

Gargamelle prevents divergence by grounding diffusion in the **Knaster-Tarski Fixed-Point Theorem**:
- Component stalks form a bounded meet semi-lattice (`Algebra.Lattice.BoundedMeetSemiLattice`).
- Diffusion operators update states monotonically via meet:
  $$x_u^{(k+1)} = x_u^{(k)} \wedge \bigwedge_{e = (u, v)} \rho_{e}^{\dagger}(\rho_v(x_v^{(k)}))$$
- Because the lattice is finite and the operator is order-preserving, the sequence monotonically descends down the lattice, guaranteeing finite termination at the unique greatest lower bound.

---

## 2. Harmonic Convergence in `gargamelle-sheaf`

This convergence is executed via [`diffuseUntilHarmonic`](../../../../packages/gargamelle-sheaf/src/Gargamelle/Sheaf/Diffusion.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-sheaf/docs/Gargamelle-Sheaf-Diffusion.html#v:diffuseUntilHarmonic)):

```haskell:ignore
diffuseUntilHarmonic :: (Ord vId, Eq stalk, BoundedMeetSemiLattice stalk)
                     => Int -> CellularSheaf vId eId stalk edgeStalk -> CellularSheaf vId eId stalk edgeStalk
```

If components agree on an achievable contract, the diffusion converges to zero discrepancy; if irreconcilable conflicts exist, the process terminates and exposes the conflict directly to cohomological obstruction localization.
