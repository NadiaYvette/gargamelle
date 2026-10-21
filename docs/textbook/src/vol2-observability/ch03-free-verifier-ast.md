# Chapter 3: The Free Verifier AST

**Volume II:** Reified Observability & Proof Synthesis  
**Production Type:** [`Verifier`](../../../../packages/gargamelle-model/src/Gargamelle/Model/Satisfaction.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-model/docs/Gargamelle-Model-Satisfaction.html#t:Verifier))

---

## 1. Contravariant Product & Sum Verification

Verification conditions are frequently composed using conjunction (verifying that all component invariants hold) and disjunction (verifying that at least one branch holds).

In functional programming, this corresponds directly to the `Divisible` and `Decidable` contravariant typeclasses. Gargamelle reifies these algebraic structures into a free tree:

```haskell:ignore
data Verifier model where
  AtomCheck  :: Text -> (model -> Bool) -> Verifier model
  DivideV    :: (model -> (m1, m2)) -> Verifier m1 -> Verifier m2 -> Verifier model
  ChooseV    :: (model -> Either m1 m2) -> Verifier m1 -> Verifier m2 -> Verifier model
  ConquerV   :: Verifier model
  LoseV      :: (model -> Void) -> Verifier model
  ContramapV :: (model -> model') -> Verifier model' -> Verifier model
```

---

## 2. Evidence Accumulation

When [`runVerifier`](../../../../packages/gargamelle-model/src/Gargamelle/Model/Satisfaction.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-model/docs/Gargamelle-Model-Satisfaction.html#v:runVerifier)) executes against a candidate model, it does not return a lossy boolean. Instead, it accumulates structural [`Evidence`](../../../../packages/gargamelle-model/src/Gargamelle/Model/Satisfaction.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-model/docs/Gargamelle-Model-Satisfaction.html#t:Evidence)):
- `VerifiedSection`: A certified trace documenting which atoms and branches were validated.
- `Counterexample`: The exact path, model values, and failing assertions, allowing CEGIS state machines to localize regressions.
