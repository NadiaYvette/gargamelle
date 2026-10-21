# Chapter 4: Dual Assume-Guarantee Contracts

**Volume II:** Reified Observability & Proof Synthesis  
**Production Type:** [`AGContract`](../../../../packages/gargamelle-logic/src/Gargamelle/Logic/Contract.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-logic/docs/Gargamelle-Logic-Contract.html#t:AGContract))

---

## 1. Contravariance and the Inverted Lattice

An Assume-Guarantee (A-G) contract $(A, G)$ states:
> *"If the environment satisfies assumption $A$, then the component guarantees property $G$."*

When refining or meeting two contracts $(A_1, G_1)$ and $(A_2, G_2)$, the contract meets contravariantly:
- The component **weakens** its assumptions (accepting a larger set of environments).
- The component **strengthens** its guarantees (offering more precise postconditions).

In order-theoretic terms, refinement meet ($\wedge$) must take the **join** ($\vee$) of assumptions while taking the **meet** ($\wedge$) of guarantees!

---

## 2. Formalization via `Algebra.Lattice.Op`

Rather than implementing manual ad-hoc sign checks, Gargamelle formalizes assumption inversion using `Algebra.Lattice.Op`:

```haskell:ignore
data AGContract a g = AGContract
  { agAssumption :: Op a
  , agGuarantee  :: g
  } deriving (Eq, Show, Generic)
```

By wrapping assumptions in `Op a`, the standard `Lattice` instance automatically computes the correct meet-refinement:

$$(A_1, G_1) \wedge (A_2, G_2) = (A_1 \vee_{\text{base}} A_2, G_1 \wedge_{\text{base}} G_2)$$

This structure guarantees that contract compositions preserve circular soundness ([`verifyCircularAG`](../../../../packages/gargamelle-logic/src/Gargamelle/Logic/Contract.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-logic/docs/Gargamelle-Logic-Contract.html#v:verifyCircularAG))), eliminating deadlock hazards when composing distributed microservice contracts in `sarutahiko`.
