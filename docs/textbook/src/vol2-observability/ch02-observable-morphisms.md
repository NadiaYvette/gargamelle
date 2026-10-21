# Chapter 2: Observable Morphisms (ObsMor)

**Volume II:** Reified Observability & Proof Synthesis  
**Production Type:** [`ObsMor`](../../../../packages/gargamelle-logic/src/Gargamelle/Logic/Defunctionalize.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-logic/docs/Gargamelle-Logic-Defunctionalize.html#t:ObsMor))

---

## 1. Constructing the Observable Category

The data type [`ObsMor a b`](../../../../packages/gargamelle-logic/src/Gargamelle/Logic/Defunctionalize.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-logic/docs/Gargamelle-Logic-Defunctionalize.html#t:ObsMor)) represents reified morphisms between types `a` and `b`:

```haskell:ignore
data ObsMor a b where
  ObsId       :: ObsMor a a
  ObsComp     :: ObsMor b c -> ObsMor a b -> ObsMor a c
  ObsConst    :: b -> ObsMor a b
  ObsNamed    :: Text -> (a -> b) -> ObsMor a b
  ObsFirst    :: ObsMor a b -> ObsMor (a, c) (b, c)
  ObsSecond   :: ObsMor a b -> ObsMor (c, a) (c, b)
  ObsLeft     :: ObsMor a b -> ObsMor (Either a c) (Either b c)
  ObsRight    :: ObsMor a b -> ObsMor (Either c a) (Either c b)
  ObsParallel :: ObsMor a b -> ObsMor c d -> ObsMor (a, c) (b, d)
  ObsFanout   :: ObsMor a b -> ObsMor a c -> ObsMor a (b, c)
  ObsFanin    :: ObsMor a c -> ObsMor b c -> ObsMor (Either a b) c
```

[`ObsMor`](../../../../packages/gargamelle-logic/src/Gargamelle/Logic/Defunctionalize.hs) forms an instance of `Category`, `Profunctor`, `Strong` (Cartesian monoidal arrows), and `Choice` (co-Cartesian sum arrows).

---

## 2. Structural Inspection

Unlike functions, any [`ObsMor`](../../../../packages/gargamelle-logic/src/Gargamelle/Logic/Defunctionalize.hs) arrow can be queried prior to execution via [`inspectObsMor`](../../../../packages/gargamelle-logic/src/Gargamelle/Logic/Defunctionalize.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-logic/docs/Gargamelle-Logic-Defunctionalize.html#v:inspectObsMor)):

```haskell:ignore
inspectObsMor :: ObsMor a b -> [Text]
```

This returns the full sequence of intermediate stages, named operations, and projection steps, providing `sarutahiko` with complete visibility into candidate patch semantics.
