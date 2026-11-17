{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE StrictData #-}

module Darcs.Patch.Prim.Structural
  ( SetOp (..)
  , CabalField (..)
  , HsHeaderSection (..)
  , StructuralPrim (..)
  , invertSetOp
  , invertStructural
  , commuteStructural
  ) where

import Data.ByteString (ByteString)
import Data.Kind (Type)
import Data.Text (Text)
import Darcs.Patch.Witnesses (Invert(..), Commute(..), (:>)(..))

data SetOp
  = SetInsert
  | SetDelete
  deriving (Eq, Ord, Show)

invertSetOp :: SetOp -> SetOp
invertSetOp SetInsert = SetDelete
invertSetOp SetDelete = SetInsert

data CabalField
  = CabalExposedModules
  | CabalOtherModules
  | CabalBuildDepends
  | CabalDefaultExtensions
  deriving (Eq, Ord, Show)

data HsHeaderSection
  = HsLanguagePragmas
  | HsExportList
  | HsImportList
  deriving (Eq, Ord, Show)

-- | Witnessed structural patch primitive `StructuralPrim wX wY`
data StructuralPrim (wX :: Type) (wY :: Type) where
  -- | Order-independent finite-set operation on a .cabal stanza field
  PrimCabalSet
    :: !FilePath
    -> !CabalField
    -> !SetOp
    -> !Text
    -> StructuralPrim wX wY

  -- | Order-independent finite-set operation on a Haskell module header
  PrimHsHeaderSet
    :: !FilePath
    -> !HsHeaderSection
    -> !SetOp
    -> !Text
    -> StructuralPrim wX wY

  -- | Symbol-keyed AST declaration replacement (replaces unified diff hunks!)
  PrimDeclRewrite
    :: !FilePath
    -> !Text       -- ^ Top-level declaration / symbol name
    -> !Text       -- ^ Expected before-AST text
    -> !Text       -- ^ Replacement after-AST text
    -> StructuralPrim wX wY

  -- | Classic Darcs line-hunk fallback for unstructured files
  PrimLineHunk
    :: !FilePath
    -> !Int        -- ^ 1-based line offset
    -> ![ByteString]
    -> ![ByteString]
    -> StructuralPrim wX wY

deriving stock instance Eq (StructuralPrim wX wY)
deriving stock instance Show (StructuralPrim wX wY)

invertStructural :: StructuralPrim wX wY -> StructuralPrim wY wX
invertStructural = \case
  PrimCabalSet fp fld op item ->
    PrimCabalSet fp fld (invertSetOp op) item
  PrimHsHeaderSet fp sec op item ->
    PrimHsHeaderSet fp sec (invertSetOp op) item
  PrimDeclRewrite fp sym oldAst newAst ->
    PrimDeclRewrite fp sym newAst oldAst
  PrimLineHunk fp off oldLines newLines ->
    PrimLineHunk fp off newLines oldLines

instance Invert StructuralPrim where
  invert = invertStructural

instance Commute StructuralPrim where
  commute (p :> q) = case commuteStructural (p, q) of
    Just (q', p') -> Just (q' :> p')
    Nothing       -> Nothing

-- | Commutes two sequential structural primitives `(p :> q)` into `Just (q' :> p')`
--   whenever they are parallel-independent.
commuteStructural
  :: (StructuralPrim wX wY, StructuralPrim wY wZ)
  -> Maybe (StructuralPrim wX wY', StructuralPrim wY' wZ)
commuteStructural = \case
  -- 1. Cabal set operations commute unless they touch the exact same (file, field, item) with opposite ops
  (PrimCabalSet fp1 fld1 op1 it1, PrimCabalSet fp2 fld2 op2 it2)
    | (fp1, fld1, it1) /= (fp2, fld2, it2) ->
        Just (PrimCabalSet fp2 fld2 op2 it2, PrimCabalSet fp1 fld1 op1 it1)
    | otherwise -> Nothing

  -- 2. Haskell header set operations commute for distinct items
  (PrimHsHeaderSet fp1 s1 op1 it1, PrimHsHeaderSet fp2 s2 op2 it2)
    | (fp1, s1, it1) /= (fp2, s2, it2) ->
        Just (PrimHsHeaderSet fp2 s2 op2 it2, PrimHsHeaderSet fp1 s1 op1 it1)
    | otherwise -> Nothing

  -- 3. Symbol-keyed declaration rewrites commute whenever they target different files OR different symbols!
  (PrimDeclRewrite fp1 sym1 o1 n1, PrimDeclRewrite fp2 sym2 o2 n2)
    | (fp1, sym1) /= (fp2, sym2) ->
        Just (PrimDeclRewrite fp2 sym2 o2 n2, PrimDeclRewrite fp1 sym1 o1 n1)
    | otherwise -> Nothing

  -- 4. Header edits and declaration body rewrites in the same .hs file ALWAYS commute!
  (PrimHsHeaderSet fp1 s1 op1 it1, PrimDeclRewrite fp2 sym2 o2 n2) ->
    Just (PrimDeclRewrite fp2 sym2 o2 n2, PrimHsHeaderSet fp1 s1 op1 it1)
  (PrimDeclRewrite fp1 sym1 o1 n1, PrimHsHeaderSet fp2 s2 op2 it2) ->
    Just (PrimHsHeaderSet fp2 s2 op2 it2, PrimDeclRewrite fp1 sym1 o1 n1)

  -- 5. Cabal set and Haskell headers or decl rewrites ALWAYS commute!
  (PrimCabalSet fp1 f1 o1 it1, PrimHsHeaderSet fp2 s2 o2 it2) ->
    Just (PrimHsHeaderSet fp2 s2 o2 it2, PrimCabalSet fp1 f1 o1 it1)
  (PrimHsHeaderSet fp1 s1 o1 it1, PrimCabalSet fp2 f2 o2 it2) ->
    Just (PrimCabalSet fp2 f2 o2 it2, PrimHsHeaderSet fp1 s1 o1 it1)
  (PrimCabalSet fp1 f1 o1 it1, PrimDeclRewrite fp2 sym2 o2 n2) ->
    Just (PrimDeclRewrite fp2 sym2 o2 n2, PrimCabalSet fp1 f1 o1 it1)
  (PrimDeclRewrite fp1 sym1 o1 n1, PrimCabalSet fp2 f2 o2 it2) ->
    Just (PrimCabalSet fp2 f2 o2 it2, PrimDeclRewrite fp1 sym1 o1 n1)

  -- 6. Line hunk commutation with automatic offset shifting
  (PrimLineHunk fp1 off1 old1 new1, PrimLineHunk fp2 off2 old2 new2)
    | fp1 /= fp2 ->
        Just (PrimLineHunk fp2 off2 old2 new2, PrimLineHunk fp1 off1 old1 new1)
    | off1 + length new1 < off2 ->
        let delta = length new1 - length old1
        in Just ( PrimLineHunk fp2 (off2 - delta) old2 new2
                , PrimLineHunk fp1 off1 old1 new1
                )
    | off2 + length old2 < off1 ->
        let delta = length new2 - length old2
        in Just ( PrimLineHunk fp2 off2 old2 new2
                , PrimLineHunk fp1 (off1 + delta) old1 new1
                )
    | otherwise -> Nothing

  -- 7. Line hunks and structural edits commute across different files
  (PrimLineHunk fp1 off1 old1 new1, PrimCabalSet fp2 f2 o2 it2)
    | fp1 /= fp2 -> Just (PrimCabalSet fp2 f2 o2 it2, PrimLineHunk fp1 off1 old1 new1)
  (PrimCabalSet fp1 f1 o1 it1, PrimLineHunk fp2 off2 old2 new2)
    | fp1 /= fp2 -> Just (PrimLineHunk fp2 off2 old2 new2, PrimCabalSet fp1 f1 o1 it1)
  (PrimLineHunk fp1 off1 old1 new1, PrimHsHeaderSet fp2 s2 o2 it2)
    | fp1 /= fp2 -> Just (PrimHsHeaderSet fp2 s2 o2 it2, PrimLineHunk fp1 off1 old1 new1)
  (PrimHsHeaderSet fp1 s1 o1 it1, PrimLineHunk fp2 off2 old2 new2)
    | fp1 /= fp2 -> Just (PrimLineHunk fp2 off2 old2 new2, PrimHsHeaderSet fp1 s1 o1 it1)
  (PrimLineHunk fp1 off1 old1 new1, PrimDeclRewrite fp2 sym2 o2 n2)
    | fp1 /= fp2 -> Just (PrimDeclRewrite fp2 sym2 o2 n2, PrimLineHunk fp1 off1 old1 new1)
  (PrimDeclRewrite fp1 sym1 o1 n1, PrimLineHunk fp2 off2 old2 new2)
    | fp1 /= fp2 -> Just (PrimLineHunk fp2 off2 old2 new2, PrimDeclRewrite fp1 sym1 o1 n1)

  _ -> Nothing
