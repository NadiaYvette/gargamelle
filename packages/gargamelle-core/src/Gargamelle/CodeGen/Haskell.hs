{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gargamelle.CodeGen.Haskell
  ( -- * Code Generation Entrypoint
    lowerSynTermToHaskell
  , generateModule
  , lowerLiquidPred
  , renderRelOp
  , renderBinOp
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import Gargamelle.Core.Institution.Liquid
  ( BinOp (..)
  , LiquidPred (..)
  , RelOp (..)
  , SynTerm (..)
  )

--------------------------------------------------------------------------------
-- 1. Lowering SynTerm ASTs to Idiomatic Zero-Cost Haskell
--------------------------------------------------------------------------------

-- | Lower a verified SynTerm AST into Polytropos and Penelope Haskell syntax.
lowerSynTermToHaskell :: SynTerm -> Text
lowerSynTermToHaskell = \case
  TVar v ->
    v
  TIntLit i ->
    T.pack (show i)
  TBoolLit True ->
    "True"
  TBoolLit False ->
    "False"
  TLam x body ->
    "(\\" <> x <> " -> " <> lowerSynTermToHaskell body <> ")"
  TIf guardPred thenBranch elseBranch ->
    T.unlines
      [ "if " <> lowerLiquidPred guardPred
      , "  then " <> lowerSynTermToHaskell thenBranch
      , "  else " <> lowerSynTermToHaskell elseBranch
      ]
  TEffPure innerTerm ->
    "pure (" <> lowerSynTermToHaskell innerTerm <> ")"
  TEffBind x opTerm contTerm ->
    T.unlines
      [ "do"
      , "  " <> x <> " <- " <> lowerSynTermToHaskell opTerm
      , "  " <> lowerSynTermToHaskell contTerm
      ]
  TApp (TVar fn) args
    -- Polytropos RecordF Field Selection: getF_l r -> Polytropos.getF @"l" r
    | "getF_" `T.isPrefixOf` fn, [arg] <- args ->
        let lbl = T.drop 5 fn
        in "Polytropos.getF @\"" <> lbl <> "\" " <> wrapAtom (lowerSynTermToHaskell arg)
    -- Polytropos RecordF Field Update: setF_l val r -> Polytropos.setF @"l" val r
    | "setF_" `T.isPrefixOf` fn, [val, recArg] <- args ->
        let lbl = T.drop 5 fn
        in "Polytropos.setF @\"" <> lbl <> "\" " <> wrapAtom (lowerSynTermToHaskell val) <> " " <> wrapAtom (lowerSynTermToHaskell recArg)
    -- Polytropos VariantF Tag Match: matchTagF_l u -> Polytropos.matchF @"l" u
    | "matchTagF_" `T.isPrefixOf` fn, [arg] <- args ->
        let lbl = T.drop 10 fn
        in "Polytropos.matchF @\"" <> lbl <> "\" " <> wrapAtom (lowerSynTermToHaskell arg)
    -- Polytropos VariantF Injection: injF_l x -> Polytropos.injF @"l" x
    | "injF_" `T.isPrefixOf` fn, [arg] <- args ->
        let lbl = T.drop 5 fn
        in "Polytropos.injF @\"" <> lbl <> "\" " <> wrapAtom (lowerSynTermToHaskell arg)
    -- Polytropos Statically Verified Total Elimination: absurdVariantF u -> Polytropos.absurdVariant u
    | fn == "absurdVariantF", [arg] <- args ->
        "Polytropos.absurdVariant " <> wrapAtom (lowerSynTermToHaskell arg)
    -- Penelope Effectful Operation: perform_E st -> Penelope.perform @E st
    | "perform_" `T.isPrefixOf` fn, [arg] <- args ->
        let eff = T.drop 8 fn
        in "Penelope.perform @" <> eff <> " " <> wrapAtom (lowerSynTermToHaskell arg)
    | fn == "add", [l, r] <- args ->
        wrapAtom (lowerSynTermToHaskell l) <> " + " <> wrapAtom (lowerSynTermToHaskell r)
    | fn == "sub", [l, r] <- args ->
        wrapAtom (lowerSynTermToHaskell l) <> " - " <> wrapAtom (lowerSynTermToHaskell r)
    -- Standard Function Application
    | otherwise ->
        let renderedArgs = T.unwords (map (wrapAtom . lowerSynTermToHaskell) args)
        in if null args then fn else fn <> " " <> renderedArgs
  TApp nonVarHead args ->
    let renderedHead = wrapAtom (lowerSynTermToHaskell nonVarHead)
        renderedArgs = T.unwords (map (wrapAtom . lowerSynTermToHaskell) args)
    in renderedHead <> " " <> renderedArgs

--------------------------------------------------------------------------------
-- 2. Helper Renderers for Predicates and Syntax Wrapping
--------------------------------------------------------------------------------

lowerLiquidPred :: LiquidPred -> Text
lowerLiquidPred = \case
  PTrue ->
    "True"
  PFalse ->
    "False"
  PVar v ->
    v
  PIntLit i ->
    T.pack (show i)
  PEmptySet _ ->
    "Data.Set.empty"
  PMeasureApp m e
    | "sel_" `T.isPrefixOf` m ->
        "Polytropos.getF @\"" <> T.drop 4 m <> "\" " <> wrapAtom (lowerLiquidPred e)
    | "vpayload_" `T.isPrefixOf` m ->
        "Polytropos.matchF @\"" <> T.drop 9 m <> "\" " <> wrapAtom (lowerLiquidPred e)
    | otherwise ->
        m <> " " <> wrapAtom (lowerLiquidPred e)
  PFieldProj l e ->
    "Polytropos.getF @\"" <> l <> "\" " <> wrapAtom (lowerLiquidPred e)
  PVariantTag t e ->
    "Polytropos.hasTag @\"" <> t <> "\" " <> wrapAtom (lowerLiquidPred e)
  PNot p ->
    "not (" <> lowerLiquidPred p <> ")"
  PAnd ps ->
    T.intercalate " && " (map (wrapAtom . lowerLiquidPred) ps)
  POr ps ->
    T.intercalate " || " (map (wrapAtom . lowerLiquidPred) ps)
  PRel op l r ->
    lowerLiquidPred l <> " " <> renderRelOp op <> " " <> lowerLiquidPred r
  PBinOp op l r ->
    lowerLiquidPred l <> " " <> renderBinOp op <> " " <> lowerLiquidPred r
  PImplies l r ->
    "not (" <> lowerLiquidPred l <> ") || (" <> lowerLiquidPred r <> ")"
  PIff l r ->
    "(" <> lowerLiquidPred l <> ") == (" <> lowerLiquidPred r <> ")"
  PLiquidHole h _ ->
    h

renderRelOp :: RelOp -> Text
renderRelOp = \case
  Eq -> "=="
  Neq -> "/="
  Lt -> "<"
  Le -> "<="
  Gt -> ">"
  Ge -> ">="
  SetMember -> "`Data.Set.member`"
  SetSubset -> "`Data.Set.isSubsetOf`"

renderBinOp :: BinOp -> Text
renderBinOp = \case
  Add -> "+"
  Sub -> "-"
  Mul -> "*"
  SetUnion -> "`Data.Set.union`"
  SetIntersect -> "`Data.Set.intersection`"
  SetDiff -> "`Data.Set.difference`"

wrapAtom :: Text -> Text
wrapAtom t
  | T.any (== ' ') t && not (isAlreadyWrapped t) = "(" <> t <> ")"
  | otherwise = t
  where
    isAlreadyWrapped s =
      T.isPrefixOf "(" s && T.isSuffixOf ")" s

--------------------------------------------------------------------------------
-- 3. Complete Module Wrapper Generation
--------------------------------------------------------------------------------

-- | Generates a complete, self-contained Haskell module embedding the verified term.
generateModule :: Text -> Text -> SynTerm -> Text
generateModule modName funcName term =
  T.unlines
    [ "{-# LANGUAGE DataKinds #-}"
    , "{-# LANGUAGE OverloadedStrings #-}"
    , "{-# LANGUAGE TypeApplications #-}"
    , ""
    , "module " <> modName <> " where"
    , ""
    , "import qualified Polytropos"
    , "import qualified Penelope"
    , "import qualified Data.Set"
    , ""
    , "-- | Verified by Gargamelle + Synquid (H0 global section, zero runtime partial matches)."
    , funcName <> " :: _"
    , funcName <> " = " <> lowerSynTermToHaskell term
    ]
