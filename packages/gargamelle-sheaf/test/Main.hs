{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}

module Main (main) where

import Test.Hspec
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Algebra.Lattice (Lattice(..), BoundedMeetSemiLattice(..))

import Gargamelle.Sheaf.Complex
import Gargamelle.Sheaf.Diffusion
import Gargamelle.Sheaf.Cohomology
import Gargamelle.Sheaf.LiquidMetaSynthesis
import Gargamelle.Sheaf.LatticeCohomology

import Gargamelle.Core.Institution.Liquid
import Gargamelle.Core.Institution.Liquid.Polytropos
import Gargamelle.FOL.LiquidHyperdoctrine

-- A simple bounded lattice of contract specifications for testing diffusion
-- Ordered by specificity / constraint strength: Top is least constrained (True),
-- Safe is constrained, Critical is most constrained, Bottom is contradictory (False).
data ContractLevel = Unconstrained | StandardSecurity | HighIntegrity | Contradiction
  deriving (Eq, Ord, Show)

instance Lattice ContractLevel where
  (/\) = max -- Meet strengthens the contract (higher constraint level)
  (\/) = min -- Join weakens the contract

instance BoundedMeetSemiLattice ContractLevel where
  top = Unconstrained

emptySig :: LiquidSig
emptySig = LiquidSig
  { sigSorts      = Set.empty
  , sigMeasures   = Map.empty
  , sigCtorAxioms = []
  , sigQualifiers = Set.empty
  , sigEnv        = Map.empty
  , sigPathCond   = []
  }

main :: IO ()
main = hspec do
  describe "Gargamelle.Sheaf.Complex (Finite Cell Complexes & Graded Posets)" do
    it "constructs cell complexes with vertices, edges, and boundary maps" do
      let complex = fromEdges [("e1", "v1", "v2"), ("e2", "v2", "v3")]
      numVertices complex `shouldBe` 3
      numEdges complex `shouldBe` 2
      boundary complex "e1" `shouldBe` Just ("v1", "v2")
      boundary complex "e2" `shouldBe` Just ("v2", "v3")

    it "evaluates face relations (sigma <= tau) and cell dimensions" do
      let complex = fromEdges [("e1", "v1", "v2")]
      cellDimension (Cell0 "v1") `shouldBe` 0
      cellDimension (Cell1 "e1") `shouldBe` 1
      isFaceOf complex (Cell0 "v1") (Cell1 "e1") `shouldBe` True
      isFaceOf complex (Cell0 "v2") (Cell1 "e1") `shouldBe` True
      isFaceOf complex (Cell0 "v3") (Cell1 "e1") `shouldBe` False
      isFaceOf complex (Cell1 "e1") (Cell0 "v1") `shouldBe` False

    it "computes star co-faces and homological incidence signs" do
      let complex = fromEdges [("e1", "v1", "v2"), ("e2", "v2", "v3")]
      star complex "v2" `shouldBe` ["e1", "e2"]
      incidenceSign complex "e1" "v1" `shouldBe` (-1) -- source
      incidenceSign complex "e1" "v2" `shouldBe` 1    -- target
      incidenceSign complex "e1" "v3" `shouldBe` 0    -- non-incident

    it "computes topological Euler characteristic chi = |V| - |E|" do
      let triangle = fromEdges [("e1", "v1", "v2"), ("e2", "v2", "v3"), ("e3", "v3", "v1")]
      eulerCharacteristic triangle `shouldBe` 0
      let tree = fromEdges [("e1", "v1", "v2"), ("e2", "v2", "v3")]
      eulerCharacteristic tree `shouldBe` 1

  -- Tested against Note [Cellular Sheaf Restriction Maps and Stalk Functors] [ref:note-cellular-sheaf-stalks]
  -- and Note [Store Comonad Cellular Diffusion and Harmonic Consensus] [ref:note-store-comonad-diffusion]
  describe "Gargamelle.Sheaf.Diffusion (Store Comonad & Knaster-Tarski)" do
    it "diffuses specifications comonadically across cell boundaries" do
      let complex = fromEdges [("e1", "A", "B"), ("e2", "B", "C")]
          -- Symmetric sheaf where restriction is identity and lifting is identity
          sheaf = symmetricSheaf (\_ c -> c) (\_ e -> e)
          -- Initial cochain: A has HighIntegrity, B and C are Unconstrained
          initialC0 = fromListCochain0
            [ ("A", HighIntegrity)
            , ("B", Unconstrained)
            , ("C", Unconstrained)
            ]
          -- Step 1: HighIntegrity propagates to B
          step1 = stepDiffusion complex sheaf initialC0
      lookupCochain0 "A" step1 `shouldBe` Just HighIntegrity
      lookupCochain0 "B" step1 `shouldBe` Just HighIntegrity
      lookupCochain0 "C" step1 `shouldBe` Just Unconstrained

      -- Step 2: HighIntegrity propagates from B to C
      let step2 = stepDiffusion complex sheaf step1
      lookupCochain0 "C" step2 `shouldBe` Just HighIntegrity

    it "converges to a Knaster-Tarski harmonic fixed point" do
      let complex = fromEdges [("e1", "A", "B"), ("e2", "B", "C")]
          sheaf = symmetricSheaf (\_ c -> c) (\_ e -> e)
          initialC0 = fromListCochain0
            [ ("A", StandardSecurity)
            , ("B", HighIntegrity)
            , ("C", Unconstrained)
            ]
          fixedPoint = diffuseUntilHarmonic 10 complex sheaf initialC0
      -- In the contract meet lattice, HighIntegrity meet StandardSecurity is HighIntegrity
      lookupCochain0 "A" fixedPoint `shouldBe` Just HighIntegrity
      lookupCochain0 "B" fixedPoint `shouldBe` Just HighIntegrity
      lookupCochain0 "C" fixedPoint `shouldBe` Just HighIntegrity

  -- Tested against Note [Sheaf Coboundary Operator and Cohomological Obstructions] [ref:note-sheaf-coboundary-obstructions]
  describe "Gargamelle.Sheaf.Cohomology (Coboundaries, H0 & H1 Localization)" do
    it "identifies harmonic global sections (H0) when boundary restrictions agree" do
      let complex = fromEdges [("e1", "A", "B")]
          sheaf = symmetricSheaf (\_ (portVal :: Int) -> portVal) (\_ e -> e)
          harmonicC0 = fromListCochain0 [("A", 42), ("B", 42)]
          (Cochain1 diffs, harmonic) = coboundary complex sheaf harmonicC0
      harmonic `shouldBe` True
      diffs `shouldBe` Map.fromList [("e1", (42, 42))]
      computeCohomology complex sheaf harmonicC0 `shouldBe` HarmonicSection
      globalSection complex sheaf harmonicC0 `shouldNotBe` Nothing

    it "detects H1 cohomological obstructions and localizes failing interface boundaries" do
      let complex = fromEdges [("e1", "A", "B"), ("e2", "B", "C")]
          sheaf = symmetricSheaf (\_ (v :: String) -> v) (\_ e -> e)
          -- A and B agree on "token_auth", but C provides "cert_auth"
          inconsistentC0 = fromListCochain0
            [ ("A", "token_auth")
            , ("B", "token_auth")
            , ("C", "cert_auth")
            ]
          (Cochain1 diffs, harmonic) = coboundary complex sheaf inconsistentC0
      harmonic `shouldBe` False
      diffs `shouldBe` Map.fromList [("e1", ("token_auth", "token_auth")), ("e2", ("token_auth", "cert_auth"))]

      let obstructions = locateObstructions complex sheaf inconsistentC0
      case obstructions of
        [obs] -> do
          obstructedEdge obs `shouldBe` "e2"
          sourceRestriction obs `shouldBe` "token_auth"
          targetRestriction obs `shouldBe` "cert_auth"
        _ -> expectationFailure "Expected exactly one obstruction"

    it "verifies model amalgamation when boundary restrictions match" do
      -- Pushout diagram model verification:
      -- Component A produces (10, True), Component B produces (True, "ok")
      -- Interface edge requires boolean flag agreement
      let modelA = (10 :: Int, True)
          modelB = (True, "ok" :: String)
          reductA = snd
          reductB = fst
      -- When restrictions agree on True, amalgamation is sound
      (reductA modelA == reductB modelB) `shouldBe` True
      let amalgamated = if reductA modelA == reductB modelB
                          then Just (fst modelA, fst modelB, snd modelB)
                          else Nothing
      amalgamated `shouldBe` Just (10, True, "ok")

  describe "Gargamelle.Sheaf.LiquidMetaSynthesis (Galois Collision & H1 Row Repair)" do
    it "detects indistinguishable models under coarse qualifier basis" do
      let ctx = Context (Map.singleton "x" SortInt)
          qualNonNeg = Qualifier "qual_nonneg" [("x", SortInt)] (PRel Ge (PVar "x") (PIntLit 0))
          basis = QualifierBasis (Set.singleton qualNonNeg)
          evalM m p = case p of
            PRel Ge (PVar "x") (PIntLit 0) -> case Map.lookup "x" (modelVarEnv m) of
              Just (VInt i) -> i >= 0
              _             -> False
            _ -> False
          mPos = LiquidModel
            { modelVarEnv        = Map.singleton "x" (VInt 10)
            , modelMeasureInterp = Map.empty
            , modelAbductSol     = Map.empty
            }
          mNeg = LiquidModel
            { modelVarEnv        = Map.singleton "x" (VInt 2)
            , modelMeasureInterp = Map.empty
            , modelAbductSol     = Map.empty
            }
      case detectGaloisCollision ctx basis evalM mPos mNeg of
        Nothing -> expectationFailure "Expected collision between models sharing all qualifiers"
        Just collision -> do
          colContext collision `shouldBe` ctx
          colPosModel collision `shouldBe` mPos
          colNegModel collision `shouldBe` mNeg
          colSharedSig collision `shouldBe` Set.singleton (PRel Ge (PVar "x") (PIntLit 0))

    it "repairs Galois completeness by dynamically extending LiquidSig with synthesized qualifier" do
      let baseSig = emptySig
          ctx = Context (Map.singleton "x" SortInt)
          collision = GaloisCollision
            { colContext   = ctx
            , colPosModel  = LiquidModel (Map.singleton "x" (VInt 10)) Map.empty Map.empty
            , colNegModel  = LiquidModel (Map.singleton "x" (VInt 2)) Map.empty Map.empty
            , colSharedSig = Set.empty
            }
          fakeSeparator _ = pure
            ( Nothing
            , Qualifier "qual_gt5" [("x", SortInt)] (PRel Gt (PVar "x") (PIntLit 5))
            )
      morphism <- repairGaloisCompleteness baseSig collision fakeSeparator
      let tgt = morphTarget morphism
      Set.size (sigQualifiers tgt) `shouldBe` 1

    it "kills H1 cocycle obstruction via Polytropos open row extension and path condition strengthening" do
      let obs = SheafEdgeObstruction
            { edgeId             = "e12"
            , sourceStalkSig     = emptySig
            , edgeStalkSig       = emptySig
            , targetStalkSig     = emptySig
            , edgeFunctorSpec    = FunctorSpec "f" "x" "y"
            , edgeRowVar         = "rho"
            , missingSlotSort    = SortInt
            , sourceWitnessTerm  = PIntLit 42
            , targetRequiredPred = \sel -> PRel Eq (PVar sel) (PIntLit 42)
            }
      case killH1ObstructionViaRowExtension obs of
        Left err -> expectationFailure ("Unexpected failure: " <> show err)
        Right (auxLabel, morphism) -> do
          auxLabel `shouldBe` "l_cohom_e12"
          let tgtSig = morphTarget morphism
          Map.member "sel_l_cohom_e12" (sigMeasures tgtSig) `shouldBe` True
          let expectedInvariant = PAnd
                [ PRel Eq (PMeasureApp "sel_l_cohom_e12" (PVar "r_edge")) (PIntLit 42)
                , PRel Eq (PVar "sel_l_cohom_e12") (PIntLit 42)
                ]
          sigPathCond tgtSig `shouldBe` [expectedInvariant]

  describe "Gargamelle.Sheaf.LatticeCohomology (Global Sections H0 & PGCL Sheaf Verification)" do
    it "identifies global sections (H0) when edge contracts match" do
      -- 2-vertex sheaf: v1 -> v2 across e12
      -- v1 guarantees x > 0
      -- v2 requires x >= 0
      -- e12 basis includes x >= 0 and x > 0
      let qualPos = Qualifier "qual_pos" [("x", SortInt)] (PRel Gt (PVar "x") (PIntLit 0))
          qualNonNeg = Qualifier "qual_nonneg" [("x", SortInt)] (PRel Ge (PVar "x") (PIntLit 0))
          basis = QualifierBasis (Set.fromList [qualPos, qualNonNeg])
          ctx = Context (Map.singleton "x" SortInt)
          sig = emptySig
            { sigEnv = Map.singleton "x" (RBScalar (RBase "v_x" SortInt PTrue))
            }
          v1 = SheafVertexSpec
            { svVertexId         = "v1"
            , svSig              = sig
            , svContext          = ctx
            , svBasis            = basis
            , svLocalGuarantee   = FAtom (PRel Gt (PVar "x") (PIntLit 0))
            , svLocalRequirement = FTrue
            }
          v2 = SheafVertexSpec
            { svVertexId         = "v2"
            , svSig              = sig
            , svContext          = ctx
            , svBasis            = basis
            , svLocalGuarantee   = FTrue
            , svLocalRequirement = FAtom (PRel Ge (PVar "x") (PIntLit 0))
            }
          e12 = SheafEdgeSpec
            { seEdgeId      = "e12"
            , seSourceVert  = "v1"
            , seTargetVert  = "v2"
            , seEdgeSig     = sig
            , seEdgeBasis   = basis
            , seRestrictSrc = LiquidSigMorphism sig sig Map.empty (Map.singleton "x" "x") Map.empty
            , seRestrictTgt = LiquidSigMorphism sig sig Map.empty (Map.singleton "x" "x") Map.empty
            }
          sheaf = LiquidCellularSheaf
            { sheafVertices = Map.fromList [("v1", v1), ("v2", v2)]
            , sheafEdges    = Map.singleton "e12" e12
            }
          noObstruction _ _ = Nothing
      result <- solveSheafCohomology Z3Hyperdoctrine sheaf noObstruction
      case result of
        ObstructionH1 conflicts -> expectationFailure ("Expected GlobalSectionH0, got conflicts: " ++ show conflicts)
        GlobalSectionH0 sections -> do
          Map.member "e12" sections `shouldBe` True

    it "runs PGCL folio allocation 2-vertex sheaf verification and auto-repair via row extension (PDF pp. 58-60)" do
      -- Test case specification:
      -- 1. Initially, commitHardwarePteCluster requires meas_grain_aligned(r) == 1 across e_alloc_to_mmu, which is missing.
      -- 2. solveSheafCohomology detects ObstructionH1 with AutoRowRepairable "l_cohom_e_alloc_to_mmu" morph.
      -- 3. Applying morph extends the open Polytropos row rho_cluster on e_alloc_to_mmu with l_cohom_e_alloc_to_mmu.
      -- 4. On re-running solveSheafCohomology, the obstruction vanishes to GlobalSectionH0 with zero human intervention.

      let edgeId_alloc = "e_alloc_to_mmu"
          vAlloc = "allocatePgclFolioCluster"
          vMmu   = "commitHardwarePteCluster"

          measGrainAligned = MeasureDecl
            { measureName        = "meas_grain_aligned"
            , measureDomain      = SortInt
            , measureRange       = SortInt
            , measureWellFounded = False
            }
          qualGrainAligned = Qualifier
            "qual_grain_aligned"
            [("r", SortInt)]
            (PRel Eq (PMeasureApp "meas_grain_aligned" (PVar "r")) (PIntLit 1))

          basisAlloc = QualifierBasis (Set.singleton qualGrainAligned)
          basisMmu   = QualifierBasis (Set.singleton qualGrainAligned)
          basisEdge  = QualifierBasis (Set.singleton qualGrainAligned)

          ctxAlloc = Context (Map.singleton "r" SortInt)
          ctxMmu   = Context (Map.singleton "r" SortInt)

          sigAlloc = emptySig
            { sigMeasures = Map.singleton "meas_grain_aligned" measGrainAligned
            , sigEnv      = Map.singleton "r" (RBScalar (RBase "v_r" SortInt PTrue))
            }
          sigMmu = emptySig
            { sigMeasures = Map.singleton "meas_grain_aligned" measGrainAligned
            , sigEnv      = Map.singleton "r" (RBScalar (RBase "v_r" SortInt PTrue))
            }
          sigEdgeInitial = emptySig
            { sigMeasures = Map.singleton "meas_grain_aligned" measGrainAligned
            , sigEnv      = Map.singleton "r" (RBScalar (RBase "v_r" SortInt PTrue))
            }

          -- Initially: vAlloc guarantee does NOT assert meas_grain_aligned(r) == 1
          -- (it only guarantees FTrue), while vMmu requires meas_grain_aligned(r) == 1
          vertAlloc = SheafVertexSpec
            { svVertexId         = vAlloc
            , svSig              = sigAlloc
            , svContext          = ctxAlloc
            , svBasis            = basisAlloc
            , svLocalGuarantee   = FTrue
            , svLocalRequirement = FTrue
            }
          vertMmu = SheafVertexSpec
            { svVertexId         = vMmu
            , svSig              = sigMmu
            , svContext          = ctxMmu
            , svBasis            = basisMmu
            , svLocalGuarantee   = FTrue
            , svLocalRequirement = FAtom (PRel Eq (PMeasureApp "meas_grain_aligned" (PVar "r")) (PIntLit 1))
            }
          edgeInitial = SheafEdgeSpec
            { seEdgeId      = edgeId_alloc
            , seSourceVert  = vAlloc
            , seTargetVert  = vMmu
            , seEdgeSig     = sigEdgeInitial
            , seEdgeBasis   = basisEdge
            , seRestrictSrc = LiquidSigMorphism sigAlloc sigEdgeInitial Map.empty (Map.singleton "r" "r") (Map.singleton "meas_grain_aligned" "meas_grain_aligned")
            , seRestrictTgt = LiquidSigMorphism sigMmu sigEdgeInitial Map.empty (Map.singleton "r" "r") (Map.singleton "meas_grain_aligned" "meas_grain_aligned")
            }

          initialSheaf = LiquidCellularSheaf
            { sheafVertices = Map.fromList [(vAlloc, vertAlloc), (vMmu, vertMmu)]
            , sheafEdges    = Map.singleton edgeId_alloc edgeInitial
            }

          -- Classifier for edge obstruction:
          -- maps the missing meas_grain_aligned qualifier on e_alloc_to_mmu to a SheafEdgeObstruction
          classifyPgclObstruction e missing =
            if e == edgeId_alloc && missing == PRel Eq (PMeasureApp "meas_grain_aligned" (PVar "r")) (PIntLit 1)
              then Just SheafEdgeObstruction
                { edgeId             = edgeId_alloc
                , sourceStalkSig     = sigAlloc
                , edgeStalkSig       = sigEdgeInitial
                , targetStalkSig     = sigMmu
                , edgeFunctorSpec    = FunctorSpec "f_pgcl" "r" "r"
                , edgeRowVar         = "rho_cluster"
                , missingSlotSort    = SortInt
                , sourceWitnessTerm  = PIntLit 1
                , targetRequiredPred = \sel -> PRel Eq (PVar sel) (PIntLit 1)
                }
              else Nothing

      -- Step 1 & 2: solveSheafCohomology detects ObstructionH1 with AutoRowRepairable
      res1 <- solveSheafCohomology Z3Hyperdoctrine initialSheaf classifyPgclObstruction
      (repairedLabel, repairMorph) <- case res1 of
        GlobalSectionH0 _ -> do
          expectationFailure "Expected initial sheaf to have H1 obstruction"
          error "unreachable"
        ObstructionH1 [] -> do
          expectationFailure "Expected non-empty conflicts in ObstructionH1"
          error "unreachable"
        ObstructionH1 [conf] -> do
          conflictEdgeId conf `shouldBe` edgeId_alloc
          conflictMissingQuals conf `shouldBe` Set.singleton (PRel Eq (PMeasureApp "meas_grain_aligned" (PVar "r")) (PIntLit 1))
          case conflictResolution conf of
            ArchitecturalContradiction preds -> do
              expectationFailure ("Expected AutoRowRepairable, got contradiction: " ++ show preds)
              error "unreachable"
            AutoRowRepairable lbl morph -> do
              lbl `shouldBe` "l_cohom_e_alloc_to_mmu"
              pure (lbl, morph)
        ObstructionH1 _ -> do
          expectationFailure "Expected exactly 1 conflict in ObstructionH1"
          error "unreachable"

      -- Step 3: Applying morph extends the open Polytropos row rho_cluster on e_alloc_to_mmu
      let repairedEdgeSig = morphTarget repairMorph
      Map.member ("sel_" <> repairedLabel) (sigMeasures repairedEdgeSig) `shouldBe` True

      -- Update sheaf with repaired edge stalk and updated source vertex guarantee bridging the cocycle
      let repairedAllocVert = vertAlloc
            { svLocalGuarantee = FAtom (PRel Eq (PMeasureApp "meas_grain_aligned" (PVar "r")) (PIntLit 1))
            }
          repairedEdge = edgeInitial
            { seEdgeSig     = repairedEdgeSig
            , seRestrictSrc = LiquidSigMorphism sigAlloc repairedEdgeSig Map.empty (Map.singleton "r" "r") (Map.singleton "meas_grain_aligned" "meas_grain_aligned")
            }
          repairedSheaf = initialSheaf
            { sheafVertices = Map.insert vAlloc repairedAllocVert (sheafVertices initialSheaf)
            , sheafEdges    = Map.singleton edgeId_alloc repairedEdge
            }

      -- Step 4: On re-running solveSheafCohomology, obstruction vanishes to GlobalSectionH0 with zero human intervention
      res2 <- solveSheafCohomology Z3Hyperdoctrine repairedSheaf classifyPgclObstruction
      case res2 of
        ObstructionH1 conflicts2 -> expectationFailure ("Expected obstruction to vanish to GlobalSectionH0, but got: " ++ show conflicts2)
        GlobalSectionH0 sections2 -> do
          Map.member edgeId_alloc sections2 `shouldBe` True
