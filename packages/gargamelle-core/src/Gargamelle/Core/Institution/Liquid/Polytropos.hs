{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Gargamelle.Core.Institution.Liquid.Polytropos
  ( -- * Open Rows & Specifications
    OpenRow (..)
  , FunctorSpec (..)
  , MonoidFoldSpec (..)
    -- * Row Measure Registration
  , registerRecordRowMeasures
  , registerVariantRowMeasures
    -- * Polytropos Dynamic/Liquid Combinators
  , polyRecordCombinators
  , polyVariantCombinators
    -- * Morphisms & Row Tail Instantiation
  , instantiateRowTailMorphism
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import GHC.Generics (Generic)

import Gargamelle.Core.Institution.Liquid

--------------------------------------------------------------------------------
-- 1. Open Row Representation & Functor/Fold Specifications
--------------------------------------------------------------------------------

-- | An open row definition capturing known fields/branches, an optional row tail
-- variable for polymorphism (e.g. @rho@), and a set of labels forbidden from the tail (lacks).
data OpenRow = OpenRow
  { rowFields :: Map SymName LiquidSort
  , rowTail   :: Maybe SymName
  , rowLacks  :: Set SymName
  } deriving stock (Eq, Ord, Show, Generic)

-- | Functorial specification over a row payload, describing the mapping operation.
data FunctorSpec = FunctorSpec
  { functorName :: SymName
  , functorArg  :: SymName
  , functorRes  :: SymName
  } deriving stock (Eq, Ord, Show, Generic)

-- | Monoidal fold specification across row elements (e.g., total weight, element count).
data MonoidFoldSpec = MonoidFoldSpec
  { foldMeasureName :: SymName
  , foldSlotWeight  :: SymName
  , foldZero        :: Integer
  , foldCombine     :: BinOp
  } deriving stock (Eq, Ord, Show, Generic)

--------------------------------------------------------------------------------
-- 2. Record Row Measures & McCarthy Frame Axioms
--------------------------------------------------------------------------------

-- | Register field selector measures (@sel_<l>@), McCarthy frame axioms,
-- monoidal row-homomorphism axioms, and qualifier templates for a record row.
--
-- For each label @l@ in @rowFields@:
--   * Measure @sel_<l> : RecordRow r -> T_l@
--   * McCarthy frame axiom:
--     @sel_l(ext_l(x, r)) == x@
--     @sel_l'(ext_l(x, r)) == sel_l'(r)@ for @l' /= l@
--   * Monoidal row-homomorphism axiom:
--     @rowWeight(ext_l(x, r)) == slotWeight(x) + rowWeight(r)@
--   * Qualifiers for field relationships and frame invariants.
registerRecordRowMeasures
  :: SymName           -- ^ Sort/type name of the record
  -> OpenRow           -- ^ Open row definition
  -> Maybe MonoidFoldSpec -- ^ Optional monoid fold specification
  -> LiquidSig         -- ^ Base signature to extend
  -> LiquidSig
registerRecordRowMeasures rName row mFold baseSig =
  let rowSort = SortRecordRow (RowSchema (rowFields row))
      fields = Map.toList (rowFields row)

      -- 1. Selector measures: sel_<l> :: Record -> FieldType
      selMeasures = Map.fromList
        [ ( "sel_" <> l
          , MeasureDecl
              { measureName        = "sel_" <> l
              , measureDomain      = rowSort
              , measureRange       = fSort
              , measureWellFounded = False
              }
          )
        | (l, fSort) <- fields
        ]

      -- Fold measure if specified: rowWeight :: Record -> Int
      foldMeasures = case mFold of
        Nothing -> Map.empty
        Just spec -> Map.singleton
          (foldMeasureName spec)
          MeasureDecl
            { measureName        = foldMeasureName spec
            , measureDomain      = rowSort
            , measureRange       = SortInt
            , measureWellFounded = False
            }

      newMeasures = Map.union (Map.union selMeasures foldMeasures) (sigMeasures baseSig)

      -- 2. McCarthy Frame Axioms
      -- For each field l with constructor/extension ext_l(x, r):
      --   - axiom 1: sel_l(ext_l(x, r)) == x
      --   - axiom 2: for each l' /= l, sel_l'(ext_l(x, r)) == sel_l'(r)
      -- Plus monoidal homomorphism:
      --   - rowWeight(ext_l(x, r)) == slotWeight(x) + rowWeight(r)
      frameAxioms = concat
        [ let extCtor = "ext_" <> l
              params = [("x", fSort), ("r", rowSort)]
              -- sel_l(ext_l(x, r)) == x
              hitAxiom = CtorMeasureAxiom
                { axiomCtor    = extCtor
                , axiomParams  = params
                , axiomMeasure = "sel_" <> l
                , axiomBody    = PRel Eq (PMeasureApp ("sel_" <> l) (PVar "ext")) (PVar "x")
                }
              -- For l' /= l: sel_l'(ext_l(x, r)) == sel_l'(r)
              missAxioms =
                [ CtorMeasureAxiom
                    { axiomCtor    = extCtor
                    , axiomParams  = params
                    , axiomMeasure = "sel_" <> l'
                    , axiomBody    = PRel Eq
                        (PMeasureApp ("sel_" <> l') (PVar "ext"))
                        (PMeasureApp ("sel_" <> l') (PVar "r"))
                    }
                | (l', _) <- fields
                , l' /= l
                ]
              -- Monoidal row homomorphism: rowWeight(ext_l(x, r)) == slotWeight(x) + rowWeight(r)
              homAxioms = case mFold of
                Nothing -> []
                Just fspec ->
                  [ CtorMeasureAxiom
                      { axiomCtor    = extCtor
                      , axiomParams  = params
                      , axiomMeasure = foldMeasureName fspec
                      , axiomBody    = PRel Eq
                          (PMeasureApp (foldMeasureName fspec) (PVar "ext"))
                          (PBinOp (foldCombine fspec)
                            (PMeasureApp (foldSlotWeight fspec) (PVar "x"))
                            (PMeasureApp (foldMeasureName fspec) (PVar "r")))
                      }
                  ]
          in hitAxiom : (missAxioms ++ homAxioms)
        | (l, fSort) <- fields
        ]

      newAxioms = sigCtorAxioms baseSig ++ frameAxioms

      -- 3. Qualifier templates for field projection and frame preservation
      fieldQuals = Set.fromList
        [ Qualifier
            { qualName   = "Q_sel_" <> l
            , qualParams = [("v", rowSort), ("x", fSort)]
            , qualBody   = PRel Eq (PMeasureApp ("sel_" <> l) (PVar "v")) (PVar "x")
            }
        | (l, fSort) <- fields
        ]

      foldQuals = case mFold of
        Nothing -> Set.empty
        Just fspec -> Set.fromList
          [ Qualifier
              { qualName   = "Q_" <> foldMeasureName fspec <> "_ge_0"
              , qualParams = [("v", rowSort)]
              , qualBody   = PRel Ge (PMeasureApp (foldMeasureName fspec) (PVar "v")) (PIntLit (foldZero fspec))
              }
          ]

      newQuals = Set.unions [sigQualifiers baseSig, fieldQuals, foldQuals]

      newSorts = Set.insert rName (sigSorts baseSig)

  in baseSig
       { sigSorts      = newSorts
       , sigMeasures   = newMeasures
       , sigCtorAxioms = newAxioms
       , sigQualifiers = newQuals
       }

--------------------------------------------------------------------------------
-- 3. Variant Row Measures & Tag Set Refinements
--------------------------------------------------------------------------------

-- | Register variant row measures:
--   * @vtags : VariantRow r -> Set Text@
--   * @vpayload_<l> : VariantRow r -> T_l@
--   * Injection axioms:
--       @vtags(inj_l(x)) == singleton(l)@
--       @vpayload_l(inj_l(x)) == x@
--   * Qualifiers:
--       @Tag_l in vtags(v)@
registerVariantRowMeasures
  :: SymName           -- ^ Variant sort/type name
  -> OpenRow           -- ^ Variant open row definition
  -> LiquidSig         -- ^ Base signature to extend
  -> LiquidSig
registerVariantRowMeasures vName row baseSig =
  let rowSort = SortVariantRow (RowSchema (rowFields row))
      fields = Map.toList (rowFields row)

      -- Measure: vtags :: Variant -> Set Text (using SortSet (SortADT "Text" []))
      tagSort = SortADT "Text" []
      vtagsMeasure = Map.singleton
        "vtags"
        MeasureDecl
          { measureName        = "vtags"
          , measureDomain      = rowSort
          , measureRange       = SortSet tagSort
          , measureWellFounded = False
          }

      -- Payload measures: vpayload_<l> :: Variant -> T_l
      payloadMeasures = Map.fromList
        [ ( "vpayload_" <> l
          , MeasureDecl
              { measureName        = "vpayload_" <> l
              , measureDomain      = rowSort
              , measureRange       = fSort
              , measureWellFounded = False
              }
          )
        | (l, fSort) <- fields
        ]

      newMeasures = Map.unions [sigMeasures baseSig, vtagsMeasure, payloadMeasures]

      -- Injection Axioms:
      -- inj_<l>(x) has:
      --   - vpayload_<l>(inj_<l>(x)) == x
      --   - Tag_<l> in vtags(inj_<l>(x))
      injectionAxioms = concat
        [ let injCtor = "inj_" <> l
              params = [("x", fSort)]
              payloadAxiom = CtorMeasureAxiom
                { axiomCtor    = injCtor
                , axiomParams  = params
                , axiomMeasure = "vpayload_" <> l
                , axiomBody    = PRel Eq (PMeasureApp ("vpayload_" <> l) (PVar "inj")) (PVar "x")
                }
              tagAxiom = CtorMeasureAxiom
                { axiomCtor    = injCtor
                , axiomParams  = params
                , axiomMeasure = "vtags"
                , axiomBody    = PRel SetMember (PVar ("\"" <> l <> "\"")) (PMeasureApp "vtags" (PVar "inj"))
                }
          in [payloadAxiom, tagAxiom]
        | (l, fSort) <- fields
        ]

      newAxioms = sigCtorAxioms baseSig ++ injectionAxioms

      -- Tag test qualifiers: Tag_l in vtags(v)
      tagQuals = Set.fromList
        [ Qualifier
            { qualName   = "Q_tag_" <> l
            , qualParams = [("v", rowSort)]
            , qualBody   = PRel SetMember (PVar ("\"" <> l <> "\"")) (PMeasureApp "vtags" (PVar "v"))
            }
        | (l, _) <- fields
        ]

      newQuals = Set.union (sigQualifiers baseSig) tagQuals
      newSorts = Set.insert vName (sigSorts baseSig)

  in baseSig
       { sigSorts      = newSorts
       , sigMeasures   = newMeasures
       , sigCtorAxioms = newAxioms
       , sigQualifiers = newQuals
       }

--------------------------------------------------------------------------------
-- 4. Polytropos Dynamic/Liquid Combinators
--------------------------------------------------------------------------------

-- | Generate Polytropos record combinators for a given open row:
--   * @getF_<l> :: r:Record {l:T | ...} -> {v:T | v == sel_<l>(r)}@
--   * @setF_<l> :: x:T -> r:Record -> {v:Record | sel_<l>(v) == x /\ forall l' /= l. sel_l'(v) == sel_l'(r)}@
polyRecordCombinators :: OpenRow -> Map SymName RType
polyRecordCombinators row =
  let rowSort = SortRecordRow (RowSchema (rowFields row))
      fields = Map.toList (rowFields row)

      getters =
        [ ( "getF_" <> l
          , RArrow "r" (RBScalar (RBase "v_rec" rowSort PTrue))
              (RBScalar (RBase "v_res" fSort
                (PRel Eq (PVar "v_res") (PMeasureApp ("sel_" <> l) (PVar "r")))))
          )
        | (l, fSort) <- fields
        ]

      setters =
        [ ( "setF_" <> l
          , RArrow "x" (RBScalar (RBase "v_val" fSort PTrue))
              (RArrow "r" (RBScalar (RBase "v_rec" rowSort PTrue))
                (RBScalar (RBase "v_res" rowSort
                  (PAnd
                    ( PRel Eq (PMeasureApp ("sel_" <> l) (PVar "v_res")) (PVar "x")
                    : [ PRel Eq
                          (PMeasureApp ("sel_" <> l') (PVar "v_res"))
                          (PMeasureApp ("sel_" <> l') (PVar "r"))
                      | (l', _) <- fields
                      , l' /= l
                      ]
                    )))))
          )
        | (l, fSort) <- fields
        ]
  in Map.fromList (getters ++ setters)

-- | Generate Polytropos variant combinators for a given open row:
--   * @absurdVariantF :: {v:VariantEmpty | False} -> a@
--   * @injF_<l> :: x:T_l -> {v:Variant | Tag_l in vtags(v) /\ vpayload_<l>(v) == x}@
--   * @matchTagF_<l> :: v:Variant -> {b:Bool | b == (Tag_l in vtags(v))}@
--   * @narrowOutTagF_<l> :: {v:Variant | Tag_l in vtags(v)} -> {x:T_l | x == vpayload_<l>(v)}@
polyVariantCombinators :: OpenRow -> Map SymName RType
polyVariantCombinators row =
  let rowSort = SortVariantRow (RowSchema (rowFields row))
      fields = Map.toList (rowFields row)

      -- absurdVariantF :: {v:Variant | False} -> a
      absurdVar =
        ( "absurdVariantF"
        , RArrow "v"
            (RBScalar (RBase "v_in" rowSort PFalse))
            (RBScalar (RBase "v_out" (SortVar "a") PTrue))
        )

      injections =
        [ ( "injF_" <> l
          , RArrow "x" (RBScalar (RBase "v_val" fSort PTrue))
              (RBScalar (RBase "v_res" rowSort
                (PAnd
                  [ PRel SetMember (PVar ("\"" <> l <> "\"")) (PMeasureApp "vtags" (PVar "v_res"))
                  , PRel Eq (PMeasureApp ("vpayload_" <> l) (PVar "v_res")) (PVar "x")
                  ])))
          )
        | (l, fSort) <- fields
        ]

      tagMatches =
        [ ( "matchTagF_" <> l
          , RArrow "v" (RBScalar (RBase "v_in" rowSort PTrue))
              (RBScalar (RBase "v_res" SortBool
                (PIff (PVar "v_res")
                      (PRel SetMember (PVar ("\"" <> l <> "\"")) (PMeasureApp "vtags" (PVar "v"))))))
          )
        | (l, _) <- fields
        ]

      narrowers =
        [ ( "narrowOutTagF_" <> l
          , RArrow "v"
              (RBScalar (RBase "v_in" rowSort
                (PRel SetMember (PVar ("\"" <> l <> "\"")) (PMeasureApp "vtags" (PVar "v")))))
              (RBScalar (RBase "v_res" fSort
                (PRel Eq (PVar "v_res") (PMeasureApp ("vpayload_" <> l) (PVar "v")))))
          )
        | (l, fSort) <- fields
        ]
  in Map.fromList (absurdVar : (injections ++ tagMatches ++ narrowers))

--------------------------------------------------------------------------------
-- 5. Row Tail Instantiation Morphism
--------------------------------------------------------------------------------

-- | Construct a 'LiquidSigMorphism' mapping a row variable @rhoVar@ to a concrete
-- or extended row schema @targetRow@ in an institutional signature context.
instantiateRowTailMorphism
  :: SymName         -- ^ Row variable symbol name (e.g. "rho")
  -> OpenRow         -- ^ Concrete/extended target row schema
  -> LiquidSig       -- ^ Source signature containing rhoVar
  -> LiquidSig       -- ^ Target signature with rhoVar instantiated
  -> LiquidSigMorphism
instantiateRowTailMorphism rhoVar targetRow srcSig tgtSig =
  let targetSort = SortRecordRow (RowSchema (rowFields targetRow))
      sortMap = Map.singleton rhoVar targetSort
      -- Variable and measure maps default to identity
      varMap = Map.fromList [(v, v) | v <- Map.keys (sigEnv srcSig)]
      measMap = Map.fromList [(m, m) | m <- Map.keys (sigMeasures srcSig)]
  in LiquidSigMorphism
       { morphSource  = srcSig
       , morphTarget  = tgtSig
       , morphSortMap = sortMap
       , morphVarMap  = varMap
       , morphMeasMap = measMap
       }
