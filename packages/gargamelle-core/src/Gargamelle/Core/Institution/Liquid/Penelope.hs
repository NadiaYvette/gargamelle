{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Gargamelle.Core.Institution.Liquid.Penelope
  ( -- * Effect Rows & Types
    EffectRow (..)
  , EffectSort (..)
  , EffectType (..)
    -- * Effect Signature Registration
  , registerEffectSignatures
    -- * Dynamic / Liquid Effect Combinators
  , penelopeEffectCombinators
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import GHC.Generics (Generic)

import Gargamelle.Core.Institution.Liquid

--------------------------------------------------------------------------------
-- 1. Penelope Effect Row & Sort Definitions
--------------------------------------------------------------------------------

-- | Penelope algebraic effect row specifying available capabilities, an optional
-- open effect row tail (e.g., @effTail = Just "effs"@), and lacks constraints.
data EffectRow = EffectRow
  { effList  :: [SymName]
  -- ^ Ordered list of effect capabilities (e.g. ["State", "Console", "Resource"])
  , effTail  :: Maybe SymName
  -- ^ Optional effect row variable for open effect polymorphism
  , effLacks :: Set SymName
  -- ^ Prohibited effects in the tail
  } deriving stock (Eq, Ord, Show, Generic)

-- | Sort categorization for Penelope effects.
data EffectSort
  = EffSortState LiquidSort
  -- ^ State-like effect parameterised by state sort
  | EffSortResource SymName
  -- ^ Resource tracking with linear/affine token identifier
  | EffSortIO
  -- ^ Unrestricted primitive interaction
  | EffSortControl
  -- ^ Control-flow effects (exceptions, nondeterminism, coroutines)
  deriving stock (Eq, Ord, Show, Generic)

-- | Full specification of an individual effect operation.
data EffectType = EffectType
  { effOpName     :: SymName
  , effOpParams   :: [(SymName, LiquidSort)]
  , effOpResult   :: LiquidSort
  , effOpPreCond  :: LiquidPred
  , effOpPostCond :: LiquidPred
  } deriving stock (Eq, Ord, Show, Generic)

--------------------------------------------------------------------------------
-- 2. Effect Signature Registration
--------------------------------------------------------------------------------

-- | Register Penelope algebraic effect signatures in a Liquid signature:
--   * State transition measures (pre/post states)
--   * Fuel/budget resource exhaustion measures and qualifiers
--   * Effect capabilities sort
registerEffectSignatures
  :: EffectRow            -- ^ Effect row capabilities
  -> [EffectType]          -- ^ Effect operations to register
  -> Maybe SymName         -- ^ Optional fuel / budget counter measure name (e.g. "fuel")
  -> LiquidSig             -- ^ Base signature to extend
  -> LiquidSig
registerEffectSignatures effs ops mBudget baseSig =
  let effRowSort = SortEffectRow (effList effs)

      -- Register pre/post transition measures for each effect operation
      opMeasures = Map.fromList $ concat
        [ [ ( "pre_" <> effOpName op
            , MeasureDecl
                { measureName        = "pre_" <> effOpName op
                , measureDomain      = effRowSort
                , measureRange       = SortBool
                , measureWellFounded = False
                }
            )
          , ( "post_" <> effOpName op
            , MeasureDecl
                { measureName        = "post_" <> effOpName op
                , measureDomain      = effRowSort
                , measureRange       = SortBool
                , measureWellFounded = False
                }
            )
          ]
        | op <- ops
        ]

      -- Fuel / resource budget exhaustion measure
      budgetMeasures = case mBudget of
        Nothing -> Map.empty
        Just bName -> Map.singleton
          bName
          MeasureDecl
            { measureName        = bName
            , measureDomain      = effRowSort
            , measureRange       = SortInt
            , measureWellFounded = True
            }

      newMeasures = Map.unions [sigMeasures baseSig, opMeasures, budgetMeasures]

      -- Fuel / budget qualifiers: fuel(eff) > 0, fuel(eff) == 0
      budgetQuals = case mBudget of
        Nothing -> Set.empty
        Just bName -> Set.fromList
          [ Qualifier
              { qualName   = "Q_" <> bName <> "_pos"
              , qualParams = [("eff", effRowSort)]
              , qualBody   = PRel Gt (PMeasureApp bName (PVar "eff")) (PIntLit 0)
              }
          , Qualifier
              { qualName   = "Q_" <> bName <> "_zero"
              , qualParams = [("eff", effRowSort)]
              , qualBody   = PRel Eq (PMeasureApp bName (PVar "eff")) (PIntLit 0)
              }
          ]

      -- Pre/post state transition qualifiers for operations
      opQuals = Set.fromList
        [ Qualifier
            { qualName   = "Q_pre_" <> effOpName op
            , qualParams = ("eff", effRowSort) : effOpParams op
            , qualBody   = effOpPreCond op
            }
        | op <- ops
        ]

      newQuals = Set.unions [sigQualifiers baseSig, budgetQuals, opQuals]

      -- Register effect sort names
      effSortNames = Set.fromList (effList effs)
      newSorts = Set.union (sigSorts baseSig) effSortNames

  in baseSig
       { sigSorts      = newSorts
       , sigMeasures   = newMeasures
       , sigQualifiers = newQuals
       }

--------------------------------------------------------------------------------
-- 3. Penelope Effect Combinators
--------------------------------------------------------------------------------

-- | Generate Penelope effect perform and handle combinators:
--   * @perform_<effLabel>@: performs an operation under effect capability row @es@
--     requiring pre-condition and establishing post-condition.
--   * @handle_<effLabel>@: consumes an effect capability from @(effLabel : es)@,
--     handling its state or resource transition down to @es@.
penelopeEffectCombinators
  :: EffectRow            -- ^ Ambient effect row
  -> [EffectType]          -- ^ Operations to expose
  -> Map SymName RType
penelopeEffectCombinators effs ops =
  let es = effList effs

      -- perform_<op> :: params -> REffect es {v : Res | pre} {v : Res | post}
      performs =
        [ ( "perform_" <> effOpName op
          , foldr
              (\(pName, pSort) acc -> RArrow pName (RBScalar (RBase "v_arg" pSort PTrue)) acc)
              (REffect es
                (RBase "v_res" (effOpResult op) (effOpPreCond op))
                (effOpPostCond op))
              (effOpParams op)
          )
        | op <- ops
        ]

      -- handle_<op> :: (comp : REffect (effOp : es) Pre Post) -> REffect es Pre Post
      handlers =
        [ ( "handle_" <> effOpName op
          , RArrow "comp"
              (REffect (effOpName op : es)
                (RBase "v_in" (effOpResult op) (effOpPreCond op))
                (effOpPostCond op))
              (REffect es
                (RBase "v_out" (effOpResult op) (effOpPreCond op))
                (effOpPostCond op))
          )
        | op <- ops
        ]
  in Map.fromList (performs ++ handlers)
