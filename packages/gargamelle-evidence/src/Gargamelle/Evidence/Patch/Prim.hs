{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE StrictData #-}

module Gargamelle.Evidence.Patch.Prim
  ( -- * Primitives & Types
    SetOp(..)
  , CabalSection
  , HeaderSection
  , SymbolKey(..)
  , DPOSpan(..)
  , HoleId(..)
  , PrimPatch(..)
  , PatchId(..)
  , NamedPatch(..)
    -- * Category & Witnesses
  , FL(..)
  , RL(..)
  , (:>)(..)
  , (:\/:)(..)
  , (:/\:)(..)
  , Invert(..)
  , Commute(..)
  , CleanMerge(..)
    -- * Functions
  , invertPrim
  , commutePrim
  , cleanMergePrim
  ) where

import Data.ByteString (ByteString)
import Data.Kind (Type)
import Data.Set (Set)
import Data.Text (Text)
import GHC.Generics (Generic)
import Darcs.Patch.Witnesses
  ( FL(..)
  , RL(..)
  , (:>)(..)
  , (:\/:)(..)
  , (:/\:)(..)
  , Invert(..)
  , Commute(..)
  , CleanMerge(..)
  )
import Darcs.Patch.Prim.Structural (SetOp(..), invertSetOp)

type CabalSection = Text
type HeaderSection = Text

newtype SymbolKey = SymbolKey { unSymbolKey :: Text }
  deriving stock (Eq, Ord, Show, Generic)

data DPOSpan = DPOSpan
  { dpoBeforeAST :: !Text
  , dpoAfterAST  :: !Text
  } deriving stock (Eq, Ord, Show, Generic)

newtype HoleId = HoleId { unHoleId :: Text }
  deriving stock (Eq, Ord, Show, Generic)

newtype PatchId = PatchId { unPatchId :: ByteString }
  deriving stock (Eq, Ord, Show, Generic)

data NamedPatch p (wX :: Type) (wY :: Type) = NamedPatch
  { npId      :: !PatchId
  , npDeps    :: !(Set PatchId)
  , npPayload :: !(p wX wY)
  } deriving stock (Eq, Show, Generic)

-- | 5 Beyond-Darcs Structural Patch Primitives
data PrimPatch (wX :: Type) (wY :: Type) where
  -- 1. Cabal section set insertions / deletions
  PrimCabalSet
    :: !FilePath
    -> !CabalSection
    -> !SetOp
    -> !Text
    -> PrimPatch wX wY

  -- 2. Haskell header set insertions / deletions
  PrimHsHeaderSet
    :: !FilePath
    -> !HeaderSection
    -> !SetOp
    -> !Text
    -> PrimPatch wX wY

  -- 3. Declaration-keyed AST Double-Pushout rewrite
  PrimAstDPO
    :: !FilePath
    -> !SymbolKey
    -> !DPOSpan
    -> PrimPatch wX wY

  -- 4. Typed synthesis hole inside AST declaration
  PrimSynquidHole
    :: !FilePath
    -> !SymbolKey
    -> !HoleId
    -> !Text      -- ^ RSchema
    -> !Text      -- ^ QualifierBasis
    -> PrimPatch wX wY

  -- 5. Standard line hunk fallback
  PrimLineHunk
    :: !FilePath
    -> !Int       -- ^ 1-based line offset
    -> ![ByteString]
    -> ![ByteString]
    -> PrimPatch wX wY

deriving stock instance Eq (PrimPatch wX wY)
deriving stock instance Show (PrimPatch wX wY)

invertPrim :: PrimPatch wX wY -> PrimPatch wY wX
invertPrim = \case
  PrimCabalSet fp sec op item ->
    PrimCabalSet fp sec (invertSetOp op) item
  PrimHsHeaderSet fp sec op item ->
    PrimHsHeaderSet fp sec (invertSetOp op) item
  PrimAstDPO fp sym (DPOSpan beforeAST afterAST) ->
    PrimAstDPO fp sym (DPOSpan afterAST beforeAST)
  PrimSynquidHole fp sym hid schema basis ->
    PrimSynquidHole fp sym hid schema basis
  PrimLineHunk fp off oldLines newLines ->
    PrimLineHunk fp off newLines oldLines

instance Invert PrimPatch where
  invert = invertPrim

commutePrim
  :: (:>) PrimPatch PrimPatch wX wZ
  -> Maybe ((:>) PrimPatch PrimPatch wX wZ)
commutePrim (p :> q) = case (p, q) of
  -- 1. Cabal set operations
  (PrimCabalSet fp1 s1 op1 it1, PrimCabalSet fp2 s2 op2 it2)
    | (fp1, s1, it1) /= (fp2, s2, it2) ->
        Just (PrimCabalSet fp2 s2 op2 it2 :> PrimCabalSet fp1 s1 op1 it1)
    | otherwise -> Nothing

  -- 2. Haskell header set operations
  (PrimHsHeaderSet fp1 s1 op1 it1, PrimHsHeaderSet fp2 s2 op2 it2)
    | (fp1, s1, it1) /= (fp2, s2, it2) ->
        Just (PrimHsHeaderSet fp2 s2 op2 it2 :> PrimHsHeaderSet fp1 s1 op1 it1)
    | otherwise -> Nothing

  -- 3. AST DPO edits commute whenever they target different files or different declarations!
  (PrimAstDPO fp1 sym1 sp1, PrimAstDPO fp2 sym2 sp2)
    | (fp1, sym1) /= (fp2, sym2) ->
        Just (PrimAstDPO fp2 sym2 sp2 :> PrimAstDPO fp1 sym1 sp1)
    | otherwise -> Nothing

  -- 4. Holes and AST DPO edits on distinct symbols commute
  (PrimSynquidHole fp1 sym1 hid1 sch1 b1, PrimAstDPO fp2 sym2 sp2)
    | (fp1, sym1) /= (fp2, sym2) ->
        Just (PrimAstDPO fp2 sym2 sp2 :> PrimSynquidHole fp1 sym1 hid1 sch1 b1)
    | otherwise -> Nothing
  (PrimAstDPO fp1 sym1 sp1, PrimSynquidHole fp2 sym2 hid2 sch2 b2)
    | (fp1, sym1) /= (fp2, sym2) ->
        Just (PrimSynquidHole fp2 sym2 hid2 sch2 b2 :> PrimAstDPO fp1 sym1 sp1)
    | otherwise -> Nothing

  -- Distinct holes commute
  (PrimSynquidHole fp1 sym1 h1 sch1 b1, PrimSynquidHole fp2 sym2 h2 sch2 b2)
    | (fp1, sym1, h1) /= (fp2, sym2, h2) ->
        Just (PrimSynquidHole fp2 sym2 h2 sch2 b2 :> PrimSynquidHole fp1 sym1 h1 sch1 b1)
    | otherwise -> Nothing

  -- 5. Inter-domain structural commutations (Cabal, Header, AST DPO, Hole) ALWAYS commute!
  (PrimCabalSet fp1 s1 op1 it1, PrimHsHeaderSet fp2 s2 op2 it2) ->
    Just (PrimHsHeaderSet fp2 s2 op2 it2 :> PrimCabalSet fp1 s1 op1 it1)
  (PrimHsHeaderSet fp1 s1 op1 it1, PrimCabalSet fp2 s2 op2 it2) ->
    Just (PrimCabalSet fp2 s2 op2 it2 :> PrimHsHeaderSet fp1 s1 op1 it1)

  (PrimCabalSet fp1 s1 op1 it1, PrimAstDPO fp2 sym2 sp2) ->
    Just (PrimAstDPO fp2 sym2 sp2 :> PrimCabalSet fp1 s1 op1 it1)
  (PrimAstDPO fp1 sym1 sp1, PrimCabalSet fp2 s2 op2 it2) ->
    Just (PrimCabalSet fp2 s2 op2 it2 :> PrimAstDPO fp1 sym1 sp1)

  (PrimHsHeaderSet fp1 s1 op1 it1, PrimAstDPO fp2 sym2 sp2) ->
    Just (PrimAstDPO fp2 sym2 sp2 :> PrimHsHeaderSet fp1 s1 op1 it1)
  (PrimAstDPO fp1 sym1 sp1, PrimHsHeaderSet fp2 s2 op2 it2) ->
    Just (PrimHsHeaderSet fp2 s2 op2 it2 :> PrimAstDPO fp1 sym1 sp1)

  (PrimCabalSet fp1 s1 op1 it1, PrimSynquidHole fp2 sym2 h2 sch2 b2) ->
    Just (PrimSynquidHole fp2 sym2 h2 sch2 b2 :> PrimCabalSet fp1 s1 op1 it1)
  (PrimSynquidHole fp1 sym1 h1 sch1 b1, PrimCabalSet fp2 s2 op2 it2) ->
    Just (PrimCabalSet fp2 s2 op2 it2 :> PrimSynquidHole fp1 sym1 h1 sch1 b1)

  (PrimHsHeaderSet fp1 s1 op1 it1, PrimSynquidHole fp2 sym2 h2 sch2 b2) ->
    Just (PrimSynquidHole fp2 sym2 h2 sch2 b2 :> PrimHsHeaderSet fp1 s1 op1 it1)
  (PrimSynquidHole fp1 sym1 h1 sch1 b1, PrimHsHeaderSet fp2 s2 op2 it2) ->
    Just (PrimHsHeaderSet fp2 s2 op2 it2 :> PrimSynquidHole fp1 sym1 h1 sch1 b1)

  -- 6. Line hunks commute with each other when disjoint
  (PrimLineHunk fp1 off1 old1 new1, PrimLineHunk fp2 off2 old2 new2)
    | fp1 /= fp2 ->
        Just (PrimLineHunk fp2 off2 old2 new2 :> PrimLineHunk fp1 off1 old1 new1)
    | off1 + length new1 < off2 ->
        let delta = length new1 - length old1
        in Just ( PrimLineHunk fp2 (off2 - delta) old2 new2
                :> PrimLineHunk fp1 off1 old1 new1
                )
    | off2 + length old2 < off1 ->
        let delta = length new2 - length old2
        in Just ( PrimLineHunk fp2 off2 old2 new2
                :> PrimLineHunk fp1 (off1 + delta) old1 new1
                )
    | otherwise -> Nothing

  -- 7. Line hunks and structural edits commute across different files
  (PrimLineHunk fp1 off1 o1 n1, PrimCabalSet fp2 s2 op2 it2)
    | fp1 /= fp2 -> Just (PrimCabalSet fp2 s2 op2 it2 :> PrimLineHunk fp1 off1 o1 n1)
  (PrimCabalSet fp1 s1 op1 it1, PrimLineHunk fp2 off2 o2 n2)
    | fp1 /= fp2 -> Just (PrimLineHunk fp2 off2 o2 n2 :> PrimCabalSet fp1 s1 op1 it1)

  (PrimLineHunk fp1 off1 o1 n1, PrimHsHeaderSet fp2 s2 op2 it2)
    | fp1 /= fp2 -> Just (PrimHsHeaderSet fp2 s2 op2 it2 :> PrimLineHunk fp1 off1 o1 n1)
  (PrimHsHeaderSet fp1 s1 op1 it1, PrimLineHunk fp2 off2 o2 n2)
    | fp1 /= fp2 -> Just (PrimLineHunk fp2 off2 o2 n2 :> PrimHsHeaderSet fp1 s1 op1 it1)

  (PrimLineHunk fp1 off1 o1 n1, PrimAstDPO fp2 sym2 sp2)
    | fp1 /= fp2 -> Just (PrimAstDPO fp2 sym2 sp2 :> PrimLineHunk fp1 off1 o1 n1)
  (PrimAstDPO fp1 sym1 sp1, PrimLineHunk fp2 off2 o2 n2)
    | fp1 /= fp2 -> Just (PrimLineHunk fp2 off2 o2 n2 :> PrimAstDPO fp1 sym1 sp1)

  (PrimLineHunk fp1 off1 o1 n1, PrimSynquidHole fp2 sym2 h2 sch2 b2)
    | fp1 /= fp2 -> Just (PrimSynquidHole fp2 sym2 h2 sch2 b2 :> PrimLineHunk fp1 off1 o1 n1)
  (PrimSynquidHole fp1 sym1 h1 sch1 b1, PrimLineHunk fp2 off2 o2 n2)
    | fp1 /= fp2 -> Just (PrimLineHunk fp2 off2 o2 n2 :> PrimSynquidHole fp1 sym1 h1 sch1 b1)

  _ -> Nothing

instance Commute PrimPatch where
  commute = commutePrim

cleanMergePrim
  :: (:\/:) PrimPatch PrimPatch wX wY
  -> Maybe ((:/\:) PrimPatch PrimPatch wX wY)
cleanMergePrim (p :\/: q) = do
  q' :> p_inv' <- commute (invert p :> q)
  pure (q' :/\: invert p_inv')

instance CleanMerge PrimPatch where
  cleanMerge = cleanMergePrim
