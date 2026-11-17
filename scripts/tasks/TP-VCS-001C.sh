#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-VCS-001C] Setting up darcs-prim-structural ==="

PKG_DIR="packages/darcs-prim-structural"
mkdir -p "$PKG_DIR/src/Darcs/Patch/Prim"
mkdir -p "$PKG_DIR/test"

cat << 'EOF' > "$PKG_DIR/darcs-prim-structural.cabal"
cabal-version:      3.0
name:               darcs-prim-structural
version:            0.1.0.0
synopsis:           Set-Commutative Cabal Stanzas, Haskell Export/Import Sets, & AST DPO Primitives
description:        Beyond-Darcs structural patch primitives that eliminate false-positive line conflicts.
license:            BSD-3-Clause
author:             Nadia Yvette Chambers
maintainer:         nadia.yvette.chambers@ik.me
category:           Data, Development
build-type:         Simple

library
    exposed-modules:
        Darcs.Patch.Prim.Structural
    build-depends:
        base >= 4.18 && < 5,
        bytestring >= 0.10 && < 0.13,
        containers >= 0.6 && < 0.9,
        text >= 2.0 && < 3,
        darcs-witnesses >= 0.1
    hs-source-dirs:   src
    default-language: GHC2021
    ghc-options:      -Wall -O2

test-suite darcs-prim-structural-test
    type:             exitcode-stdio-1.0
    main-is:          Main.hs
    hs-source-dirs:   test
    build-depends:
        base >= 4.18 && < 5,
        bytestring,
        text,
        darcs-witnesses,
        darcs-prim-structural
    default-language: GHC2021
    ghc-options:      -Wall
EOF

cat << 'EOF' > "$PKG_DIR/src/Darcs/Patch/Prim/Structural.hs"
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
EOF

cat << 'EOF' > "$PKG_DIR/test/Main.hs"
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (unless)
import Darcs.Patch.Prim.Structural
import Darcs.Patch.Witnesses
import System.Exit (exitFailure, exitSuccess)

main :: IO ()
main = do
  putStrLn "Running darcs-prim-structural test suite..."

  -- 1. Two distinct Cabal set insertions commute
  let p1 = PrimCabalSet "pkg.cabal" CabalExposedModules SetInsert "Foo.Bar" :: StructuralPrim () ()
      p2 = PrimCabalSet "pkg.cabal" CabalExposedModules SetInsert "Foo.Baz" :: StructuralPrim () ()
  case commute (p1 :> p2) of
    Just (PrimCabalSet f2 _ _ it2 :> PrimCabalSet f1 _ _ it1) -> do
      unless (f2 == "pkg.cabal" && it2 == "Foo.Baz" && f1 == "pkg.cabal" && it1 == "Foo.Bar") $ do
        putStrLn "Failed: Cabal set commute returned incorrect values"
        exitFailure
    _ -> do
      putStrLn "Failed: Cabal set insertions should commute"
      exitFailure

  -- 2. Two distinct declaration rewrites in the same file commute
  let d1 = PrimDeclRewrite "src/Lib.hs" "funcA" "funcA = 1" "funcA = 2" :: StructuralPrim () ()
      d2 = PrimDeclRewrite "src/Lib.hs" "funcB" "funcB = True" "funcB = False" :: StructuralPrim () ()
  case commute (d1 :> d2) of
    Just (PrimDeclRewrite f2 sym2 _ _ :> PrimDeclRewrite f1 sym1 _ _) -> do
      unless (f2 == "src/Lib.hs" && sym2 == "funcB" && f1 == "src/Lib.hs" && sym1 == "funcA") $ do
        putStrLn "Failed: Decl rewrite commute returned incorrect values"
        exitFailure
    _ -> do
      putStrLn "Failed: Distinct symbol rewrites should commute"
      exitFailure

  -- 3. Invert involution
  unless (invert (invert p1) == p1 && invert (invert d1) == d1) $ do
    putStrLn "Failed: Invert involution"
    exitFailure

  putStrLn "All darcs-prim-structural tests passed successfully."
  exitSuccess
EOF

if ! grep -q "packages/darcs-prim-structural" cabal.project; then
  echo "  Adding darcs-prim-structural to cabal.project..."
  sed -i '/packages\/darcs-witnesses/i \  packages\/darcs-prim-structural' cabal.project
fi

echo "=== [TP-VCS-001C] Completed successfully ==="
