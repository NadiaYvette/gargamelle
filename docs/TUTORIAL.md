<!--
SPDX-License-Identifier: EUPL-1.2
-->
# Interactive Tutorial: Practical Institutions, Cellular Sheaves & CEGIS

**Status:** LIVING TUTORIAL · v2.1 · 2026-10-21  
**Audience:** Haskell Developers, Logicians, Verification Engineers, AI Assistants  
**Prerequisites:** Familiarity with typed functional programming and basic category/order theory.  
**Related Guides:** [`docs/NEWBIE_GUIDE.md`](NEWBIE_GUIDE.md) · [`docs/MAINTAINER_GUIDE.md`](MAINTAINER_GUIDE.md) · [`docs/DOCUMENTATION_ROLLOUT_PLAN.md`](DOCUMENTATION_ROLLOUT_PLAN.md) · [`docs/FRAMEWORK_RECOMMENDATIONS.md`](FRAMEWORK_RECOMMENDATIONS.md) · [`docs/developer/BUILD_SYSTEMS_MATRIX.md`](developer/BUILD_SYSTEMS_MATRIX.md)  

---

## Quickstart: Running Test Suites Interactively

Every concept in this tutorial corresponds to real, executable Haskell modules in this workspace:

```bash
# Test the full suite
cabal test gargamelle-logic gargamelle-model gargamelle-core gargamelle-fol \
           gargamelle-equational gargamelle-sheaf gargamelle-effect gargamelle-workflow

# Or explore in GHCi REPL
cabal repl gargamelle-workflow
```

---

# Part I: The Foundational 5-Lesson Plan

---

## Lesson 1: Reified Observable Morphisms & Free Verifiers (`gargamelle-model`)

In traditional Haskell verification libraries, predicates and verification conditions are represented as opaque functions `(a -> Bool)` or `(Model -> IO Result)`. These functions cannot be statically inspected, serialized to SQLite, or converted to SMT formulas.

`gargamelle-model` introduces **100% Observable Morphisms** (`ObsMor`):

```haskell
import Gargamelle.Model.Observable
import Gargamelle.Model.Verifier

-- Construct an introspectable morphism AST
let myMor :: ObsMor (Int, String) Bool
    myMor = ObsNamed "isPositive" (\(n, _) -> n > 0)

-- Build a Free Verifier AST using Divisible (products) and Decidable (sums)
let myVerifier :: VerifierAST (Int, String)
    myVerifier = divide (\(n, s) -> (n, s))
                        (VerifyPred "positiveInt" (ObsNamed "pos" (\n -> n > 0)))
                        (VerifyPred "nonEmptyStr" (ObsNamed "len" (\s -> not (null s))))

-- 100% Static Inspection without evaluation:
putStrLn (T.unpack (inspectVerifierPlan myVerifier))
-- Output: Divide [Pred "positiveInt", Pred "nonEmptyStr"]

-- Evaluate against a model returning an Evidence monoid:
let result = runVerifier myVerifier (42, "hello")
-- Result: VerifiedSection (success)
```

---

## Lesson 2: Categorical Institutions & Pushout Weaving (`gargamelle-core`)

Goguen-Burstall **Institutions** formalize logic independently of concrete syntax:

```haskell
import Gargamelle.Core.Institution
import Gargamelle.Core.Weaving
import Proarrow.Core

-- An Institution i provides:
-- 1. Signatures: s1, s2 :: Sig i
-- 2. Morphisms:  f :: s1 ~> s2
-- 3. Sentences:  translateSen f :: Sen i s1 -> Sen i s2
-- 4. Models:     reductMod f :: ObsMor (Mod i s2) (Mod i s1)
-- 5. The Satisfaction Condition:
--    M' |= translateSen f phi <===> reductMod f M' |= phi

-- Pushout Feature Weaving:
-- Combine a Base signature B and an Aspect signature W over an interface C:
-- weaveAspect :: (c ~> b) -> (c ~> w) -> PushoutDiagram c b w p
```

When integrating an aspect (such as authentication or logging) into a core domain model, pushout weaving computes the universal colimit object and amalgamation:
$$\mathbf{Mod}(B \amalg_C W) \cong \mathbf{Mod}(B) \times_{\mathbf{Mod}(C)} \mathbf{Mod}(W)$$

---

## Lesson 3: Streaming Host SMT Pipe to Z3 (`gargamelle-fol`)

`gargamelle-fol` connects directly to host Z3 4.16 via standard SMT-LIB2 streaming pipes:

```haskell
import Gargamelle.FOL.Z3
import qualified Data.Map.Strict as Map

-- 1. Check satisfiability and extract model
let formula = "(declare-const x Int) (declare-const y Int) (assert (= (+ x y) 10)) (assert (> x 5))"
result <- solveZ3 formula
case result of
  Sat modelMap -> do
    putStrLn $ "Satisfiable! x = " ++ Map.findWithDefault "?" "x" modelMap
  Unsat -> putStrLn "Unsatisfiable"
  Z3Error err -> putStrLn $ "Error: " ++ T.unpack err

-- 2. Verify formal validity (tautology checking)
-- Verifying whether (x > 0 ==> x >= 0) is universally valid:
validity <- verifyZ3Formula "x_pos" "(assert (not (=> (> x 0) (>= x 0))))"
-- Returns: VerifiedSection "Tautology verified by Z3"
```

---

## Lesson 4: Cellular Sheaves & Homological Fault Localization (`gargamelle-sheaf`)

Software architectures are modeled as 1-dimensional cell complexes:

```haskell
import Gargamelle.Sheaf

-- 1. Define a 1-dimensional Cell Complex: 3 services, 2 interfaces
let complex = fromEdges
      [ ("api_auth", "ServiceAuth", "ServiceGateway")
      , ("api_billing", "ServiceGateway", "ServiceBilling")
      ]

-- 2. Define a cellular sheaf over contracts
let sheaf = symmetricSheaf (\_ (c :: Text) -> c) (\_ e -> e)

-- 3. Assign local contracts across services:
-- Notice the discrepancy: ServiceGateway expects "BearerToken", but ServiceBilling expects "OAuth2Secret"
let spec = fromListCochain0
      [ ("ServiceAuth", "BearerToken")
      , ("ServiceGateway", "BearerToken")
      , ("ServiceBilling", "OAuth2Secret")
      ]

-- 4. Evaluate the coboundary operator \delta^0:
let (Cochain1 diffs, isHarmonic) = coboundary complex sheaf spec
-- isHarmonic is False!

-- 5. Pinpoint exact failing interfaces via H^1 obstruction localization:
let obstructions = locateObstructions complex sheaf spec
-- Result:
-- [ InterfaceObstruction
--     { obstructedEdge = "api_billing"
--     , sourceRestriction = "BearerToken"
--     , targetRestriction = "OAuth2Secret"
--     }
-- ]
```

The output gives exact interface names and differing values, allowing automated repair to focus precisely on the offending boundary.

---

## Lesson 5: Store Comonad Diffusion & Sheaf-Gated CEGIS (`gargamelle-workflow`)

When boundary discrepancies exist, we can reconcile them through comonadic diffusion over a contract lattice before falling back to full counterexample repair:

```haskell
import Workflow.Synthesis
import Sandbox.Effect
import Database.SQLite.Simple (open, close)

main :: IO ()
main = do
  conn <- open ":memory:"
  let complex = fromEdges [("e1", "ServiceA", "ServiceB")]
  let sheaf = symmetricSheaf (\_ (c :: Text) -> c) (\_ e -> e)
  let spec = fromListCochain0 [("ServiceA", "ProtocolV1"), ("ServiceB", "ProtocolV1")]

  let config = SheafCEGISConfig
        { cegisDbConn        = conn
        , cegisRunId         = 101
        , cegisCandidateName = "candidate_v1"
        , cegisChangeRep     = "ast_hash_v1"
        , cegisSig           = "Institution.Service"
        , cegisLimits        = defaultLimits { limitTimeoutSeconds = 5 }
        , cegisSandboxCmd    = ("echo", ["build-ok"])
        , cegisComplex       = complex
        , cegisSheaf         = sheaf
        , cegisCandidateSpec = spec
        , cegisTimestamp     = 1800000
        }

  -- Run end-to-end Sheaf-Gated CEGIS:
  -- 1. Starts run record in Beam SQLite.
  -- 2. Executes command inside Bubblewrap container isolation.
  -- 3. Steps Crem Mealy state machine through StatePropose -> StateSandboxRun -> StateCollectEvidence.
  -- 4. Checks SQLite for historical matching failures.
  -- 5. Evaluates H^1 coboundary obstruction.
  -- 6. If H^1 = 0, records verified global section into Beam SQLite and completes!
  (outcome, events) <- runSheafGatedCEGIS config
  case outcome of
    SheafCEGISSuccess (GlobalSection sec) msg ->
      putStrLn $ "Synthesis Verified! " ++ T.unpack msg
    SheafCEGISObstruction obs ->
      putStrLn $ "Obstructions located: " ++ show obs
    _ -> putStrLn "Failed"

  close conn
```
