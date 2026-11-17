{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : Gargamelle.Audit.DocTier
Description : Tiered Maalej-Robillard Documentation Verifier
Copyright   : (c) Nadia Yvette Chambers, 2026
License     : EUPL-1.2

@purpose
Verifies that exported Haskell symbols carry structured Haddock headers
satisfying Maalej-Robillard knowledge slot requirements and novelty ratios.

@behavior
Enforces Tier A (6 core knowledge slots + safety_invariant on modules and types)
and Tier B (non-tautological function docstrings and contract annotations).

@theory
Maalej-Robillard software documentation taxonomy and information-scent verification.

@contracts
Purity: Deterministic AST/CST inspection with zero external network or subprocess calls.

@pattern
Single-pass lexical state scanner over module declarations.

@example
verifyModuleDocs defaultAuditThresholds StandardModule "src/Foo.hs" content
-}

module Gargamelle.Audit.DocTier
  ( verifyModuleDocs
  , checkModuleHeader
  ) where

import Data.Char (isSpace)
import Data.Text (Text)
import qualified Data.Text as T

import Gargamelle.Audit.Scent (computeNovelStemRatio)
import Gargamelle.Audit.Types
  ( AuditThresholds (..)
  , AuditViolation (..)
  , KnowledgeSlot (..)
  , SubstrateMode (..)
  , ViolationCategory (..)
  )

-- | Verify module header, exported types (Tier A), and exported function docstrings (Tier B).
verifyModuleDocs :: AuditThresholds -> SubstrateMode -> FilePath -> Text -> [AuditViolation]
verifyModuleDocs thresholds mode path src =
  let lns = T.lines src
      headerViolations = checkModuleHeader mode path lns
      itemViolations = scanDeclarations thresholds mode path lns
  in headerViolations ++ itemViolations

checkModuleHeader :: SubstrateMode -> FilePath -> [Text] -> [AuditViolation]
checkModuleHeader mode path lns =
  let (headerComment, modLine) = extractModuleHeader lns
      requiredSlots = case mode of
        StandardModule  -> [SlotPurpose, SlotBehavior, SlotTheory, SlotContracts, SlotPattern, SlotExample]
        SubstrateModule -> [SlotPurpose, SlotBehavior, SlotTheory, SlotContracts, SlotPattern, SlotExample, SlotSafetyInvariant]
      presentSlots = findKnowledgeSlots headerComment
      missing = filter (`notElem` presentSlots) requiredSlots
  in case missing of
       [] -> []
       ms -> [AuditViolation
               { avFilePath    = path
               , avSymbol      = "module"
               , avStartLine   = 1
               , avEndLine     = max 1 modLine
               , avCategory    = MissingKnowledgeSlots ms
               , avRemediation = "Add missing Maalej-Robillard knowledge slots to module header"
               }]

extractModuleHeader :: [Text] -> (Text, Int)
extractModuleHeader lns =
  let (beforeDecls, _) = break isDeclOrImport lns
      commentLines = filter isCommentLine beforeDecls
  in (T.unlines commentLines, 1)
  where
    isDeclOrImport l =
      let s = T.stripStart l
      in "import " `T.isPrefixOf` s
         || "data " `T.isPrefixOf` s
         || "newtype " `T.isPrefixOf` s
         || "type " `T.isPrefixOf` s
         || "class " `T.isPrefixOf` s
         || ("::" `T.isInfixOf` s && not ("--" `T.isPrefixOf` s))
    isCommentLine l =
      let s = T.stripStart l
      in not ("module " `T.isPrefixOf` s)
         && not ("{-# " `T.isPrefixOf` s)
         && not (T.null s)

findKnowledgeSlots :: Text -> [KnowledgeSlot]
findKnowledgeSlots txt =
  let t = T.toLower txt
      has s = s `T.isInfixOf` t
      allSlots =
        [ (SlotPurpose, "@purpose")
        , (SlotBehavior, "@behavior")
        , (SlotTheory, "@theory")
        , (SlotContracts, "@contracts")
        , (SlotPattern, "@pattern")
        , (SlotExample, "@example")
        , (SlotSafetyInvariant, "@safety_invariant")
        ]
  in [ slot | (slot, tag) <- allSlots, has tag ]

-- | Scan declarations for exported types and functions
scanDeclarations :: AuditThresholds -> SubstrateMode -> FilePath -> [Text] -> [AuditViolation]
scanDeclarations thresholds mode path lns = go 1 False [] lns
  where
    go _ _ _ [] = []
    go lineNum inBlock docAcc (l:rest)
      | inBlock =
          let hasEnd = "-}" `T.isInfixOf` l
              inBlock' = not hasEnd
          in go (lineNum + 1) inBlock' (docAcc ++ [l]) rest
      | "{-|" `T.isInfixOf` l || "{-" `T.isInfixOf` l =
          let hasEnd = "-}" `T.isInfixOf` l
              inBlock' = not hasEnd
          in go (lineNum + 1) inBlock' (docAcc ++ [l]) rest
      | isHaddockLine l =
          go (lineNum + 1) False (docAcc ++ [l]) rest
      | isTypeDecl l =
          let typeSym = extractTypeName l
              v = checkTypeDecl mode path lineNum typeSym (T.unlines docAcc)
          in v ++ go (lineNum + 1) False [] rest
      | isFuncSig l =
          let (sym, sig) = extractFuncSig l
              v = checkFuncSig thresholds mode path lineNum sym sig (T.unlines docAcc)
          in v ++ go (lineNum + 1) False [] rest
      | otherwise =
          let docAcc' = if T.all isSpace l then [] else docAcc
          in go (lineNum + 1) False docAcc' rest

    isHaddockLine l =
      let s = T.stripStart l
      in "-- |" `T.isPrefixOf` s || "-- @" `T.isPrefixOf` s || "--" `T.isPrefixOf` s

    isTypeDecl l =
      let s = T.stripStart l
      in ("data " `T.isPrefixOf` s || "newtype " `T.isPrefixOf` s || "type " `T.isPrefixOf` s || "class " `T.isPrefixOf` s)
         && not ("deriving" `T.isPrefixOf` s)

    extractTypeName l =
      let s = T.stripStart l
          tokens = T.words s
      in case tokens of
           (_:name:_) -> fst (T.breakOn "=" (fst (T.breakOn " " name)))
           _          -> "Type"

    isFuncSig l =
      let s = T.stripStart l
      in "::" `T.isInfixOf` s
         && not ("data " `T.isPrefixOf` s)
         && not ("newtype " `T.isPrefixOf` s)
         && not ("type " `T.isPrefixOf` s)
         && not ("class " `T.isPrefixOf` s)
         && not ("--" `T.isPrefixOf` s)

    extractFuncSig l =
      let (symPart, sigPart) = T.breakOn "::" l
          sym = T.strip (fst (T.breakOn "(" symPart))
          sig = T.strip (T.drop 2 sigPart)
      in (sym, sig)

checkTypeDecl :: SubstrateMode -> FilePath -> Int -> Text -> Text -> [AuditViolation]
checkTypeDecl mode path lineNum sym doc =
  let requiredSlots = case mode of
        StandardModule  -> [SlotPurpose, SlotBehavior, SlotTheory, SlotContracts, SlotPattern, SlotExample]
        SubstrateModule -> [SlotPurpose, SlotBehavior, SlotTheory, SlotContracts, SlotPattern, SlotExample, SlotSafetyInvariant]
      presentSlots = findKnowledgeSlots doc
      missing = filter (`notElem` presentSlots) requiredSlots
  in case missing of
       [] -> []
       ms -> [AuditViolation
               { avFilePath    = path
               , avSymbol      = sym
               , avStartLine   = lineNum
               , avEndLine     = lineNum
               , avCategory    = MissingKnowledgeSlots ms
               , avRemediation = "Provide missing knowledge slots in docblock for exported type: " <> sym
               }]

checkFuncSig :: AuditThresholds -> SubstrateMode -> FilePath -> Int -> Text -> Text -> Text -> [AuditViolation]
checkFuncSig thresholds mode path lineNum sym sig doc =
  let cleanDoc = extractDocBody doc
      novelRatio = computeNovelStemRatio sym sig cleanDoc
      minRatio = minNovelStemRatio thresholds
      hasContract = checkContractAnnotation doc
      tautologyViol =
        if T.null cleanDoc || novelRatio < minRatio
          then [AuditViolation
                 { avFilePath    = path
                 , avSymbol      = sym
                 , avStartLine   = lineNum
                 , avEndLine     = lineNum
                 , avCategory    = TautologicalDocstring novelRatio minRatio
                 , avRemediation = "Increase information scent; ratio " <> T.pack (show novelRatio) <> " < required " <> T.pack (show minRatio)
                 }]
          else []
      contractViol =
        if not hasContract && mode /= SubstrateModule
          then [AuditViolation
                 { avFilePath    = path
                 , avSymbol      = sym
                 , avStartLine   = lineNum
                 , avEndLine     = lineNum
                 , avCategory    = MissingFunctionContract
                 , avRemediation = "Add @contracts / @complexity tag or domain contract keyword (O(...), invariant, guarantees, preserves)"
                 }]
          else []
  in tautologyViol ++ contractViol

extractDocBody :: Text -> Text
extractDocBody doc =
  let lns = T.lines doc
      clean l =
        let s = T.stripStart l
        in if "-- |" `T.isPrefixOf` s
             then T.strip (T.drop 4 s)
             else if "--" `T.isPrefixOf` s
               then T.strip (T.drop 2 s)
               else if "{-|" `T.isPrefixOf` s
                 then T.strip (T.drop 3 s)
                 else s
  in T.unwords (map clean lns)

checkContractAnnotation :: Text -> Bool
checkContractAnnotation doc =
  let t = T.toLower doc
      keywords =
        [ "@contracts", "@complexity", "o(", "precondition", "postcondition"
        , "invariant", "iff", "guarantees", "requires", "total", "idempotent"
        , "monotonic", "preserves"
        ]
  in any (`T.isInfixOf` t) keywords
