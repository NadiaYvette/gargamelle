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

`gargamelle-model` and `gargamelle-logic` introduce **100% Observable Morphisms** (`ObsMor`) and Free **Verifier** ASTs:

```haskell
module Tutorial.Lesson1_ObservableMorphisms where

import Gargamelle.Logic.Defunctionalize (ObsMor(..))
import Gargamelle.Model.Satisfaction (Verifier, verifyPredicate, evalVerifier, Evidence(..), inspectVerifierPlan)
import Gargamelle.Model.Structure (compilePairVerifier)

-- Construct an introspectable morphism AST
myMor :: ObsMor (Int, String) Bool
myMor = SymbolicStep "isPositive" (\(n, _) -> n > 0)

-- Build a Free Verifier AST using Divisible (products)
myVerifier :: Verifier (Int, String)
myVerifier = compilePairVerifier
  (verifyPredicate "positiveInt" (\n -> n > 0))
  (verifyPredicate "nonEmptyStr" (\s -> not (null s)))

-- 100% Static Inspection without evaluation:
inspectionPlan :: [String]
inspectionPlan = inspectVerifierPlan myVerifier
-- Evaluates to: ["Step:divide", "AtomCheck:positiveInt", "AtomCheck:nonEmptyStr"]

-- Evaluate against a model returning an Evidence monoid:
sampleEvaluation :: Evidence
sampleEvaluation = evalVerifier myVerifier (42, "hello")
-- Evaluates to: VerifiedSection
```

---

## Lesson 2: Categorical Institutions & Pushout Weaving (`gargamelle-core`)

Goguen-Burstall **Institutions** formalize logic independently of concrete syntax:

```haskell
{-# LANGUAGE TypeOperators #-}

module Tutorial.Lesson2_Institutions where

import Proarrow.Category.Instance.Unit (Unit(..))
import Gargamelle.Core.Weaving

-- An Institution i provides:
-- 1. Signatures: s1, s2 :: Sig i
-- 2. Morphisms:  f :: s1 ~> s2
-- 3. Sentences:  translateSen f :: Sen i s1 -> Sen i s2
-- 4. Models:     reductMod f :: ObsMor (Mod i s2) (Mod i s1)
-- 5. The Satisfaction Condition:
--    M' |= translateSen f phi <===> reductMod f M' |= phi

-- Pushout Feature Weaving:
-- Combine a Base signature B and an Aspect signature W over an interface C:
weaveSystem :: IO ()
weaveSystem = do
  let inclBase   = Unit
      inclAspect = Unit
  weaveAspect inclBase inclAspect $ \_injBase _injAspect -> do
    putStrLn "Aspect successfully woven into base specification over interface."
```

When integrating an aspect (such as authentication or logging) into a core domain model, pushout weaving computes the universal colimit object and amalgamation:
$$\mathbf{Mod}(B \amalg_C W) \cong \mathbf{Mod}(B) \times_{\mathbf{Mod}(C)} \mathbf{Mod}(W)$$

---

## Lesson 3: Streaming Host SMT Pipe to Z3 (`gargamelle-fol`)

`gargamelle-fol` connects directly to host Z3 4.16 via standard SMT-LIB2 streaming pipes:

```haskell
{-# LANGUAGE DataKinds #-}

module Tutorial.Lesson3_SMTZ3Pipe where

import Data.Proxy (Proxy(..))
import FirstOrder (Formula(..))
import Gargamelle.FOL.Z3 (checkFormulaZ3, verifyValidityZ3, SMTResult(..))
import Gargamelle.Model.Satisfaction (Evidence(..))

-- 1. Check satisfiability and extract countermodel
findSatisfyingModel :: IO ()
findSatisfyingModel = do
  let p = Pred (Proxy @"P") []
      q = Pred (Proxy @"Q") []
      formula = And p (Not q)
  result <- checkFormulaZ3 formula
  case result of
    Sat model -> putStrLn $ "Satisfying assignment: " ++ show model
    Unsat     -> putStrLn "Formula is unsatisfiable."
    Unknown e -> putStrLn $ "Solver inconclusive: " ++ e

-- 2. Verify formal validity (tautology checking)
-- Verifying Law of Excluded Middle: (P \/ not P)
verifyTautology :: IO ()
verifyTautology = do
  let p = Pred (Proxy @"P") []
      tautology = Or p (Not p)
  evidence <- verifyValidityZ3 tautology
  case evidence of
    VerifiedSection -> putStrLn "Tautology verified by host Z3 across all models."
    Counterexample sym _wit -> putStrLn $ "Countermodel found in " ++ sym
```

---

## Lesson 4: Cellular Sheaves & Homological Fault Localization (`gargamelle-sheaf`)

Software architectures are modeled as 1-dimensional cell complexes:

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Tutorial.Lesson4_CellularSheaves where

import Data.Text (Text)
import Gargamelle.Sheaf

runSheafLocalization :: IO ()
runSheafLocalization = do
  -- 1. Define a 1-dimensional Cell Complex: 3 services, 2 interfaces
  let (complex :: CellComplex Text Text) = fromEdges
        [ ("api_auth", "ServiceAuth", "ServiceGateway")
        , ("api_billing", "ServiceGateway", "ServiceBilling")
        ]

  -- 2. Define a cellular sheaf over contracts
  let sheaf = symmetricSheaf (\_ (c :: Text) -> c) (\_ (e :: Text) -> e)

  -- 3. Assign local contracts across services:
  -- Discrepancy: ServiceGateway expects "BearerToken", but ServiceBilling expects "OAuth2Secret"
  let spec = fromListCochain0
        [ ("ServiceAuth", "BearerToken")
        , ("ServiceGateway", "BearerToken")
        , ("ServiceBilling", "OAuth2Secret")
        ]

  -- 4. Evaluate the coboundary operator \delta^0:
  let (_diffs, isHarmonic) = coboundary complex sheaf spec
  putStrLn $ "Is globally consistent: " ++ show isHarmonic

  -- 5. Pinpoint exact failing interfaces via H^1 obstruction localization:
  let obstructions = locateObstructions complex sheaf spec
  case obstructions of
    [] -> putStrLn "System globally consistent (H^1 = 0)."
    obs -> mapM_ (\o -> putStrLn $ "Interface failure on: " ++ show (obstructedEdge o)) obs
```

The output gives exact interface names and differing values, allowing automated repair to focus precisely on the offending boundary.

---

## Lesson 5: Store Comonad Diffusion & Sheaf-Gated CEGIS (`gargamelle-workflow`)

When boundary discrepancies exist, we can reconcile them through comonadic diffusion over a contract lattice before falling back to full counterexample repair:

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Tutorial.Lesson5_SheafCEGIS where

import Database.SQLite.Simple (open, close)
import Data.Text (Text)
import qualified Data.Text as T
import Gargamelle.Sheaf
import Sandbox.Effect (defaultLimits, ResourceLimits(..))
import Workflow.Synthesis

runTutorialCEGIS :: IO ()
runTutorialCEGIS = do
  conn <- open ":memory:"
  let (complex :: CellComplex Text Text) = fromEdges [("e1", "ServiceA", "ServiceB")]
      sheaf = symmetricSheaf (\_ (c :: Text) -> c) (\_ (e :: Text) -> e)
      spec = fromListCochain0 [("ServiceA", "ProtocolV1"), ("ServiceB", "ProtocolV1")]
      config = SheafCEGISConfig
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
  (outcome, _events) <- runSheafGatedCEGIS config
  case outcome of
    SheafCEGISSuccess (GlobalSection _sec) msg ->
      putStrLn $ "Synthesis Verified! " ++ T.unpack msg
    SheafCEGISObstruction obs ->
      putStrLn $ "Obstructions located: " ++ show obs
    _ -> putStrLn "Failed or Retried"

  close conn
```
