{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : Gargamelle.Audit.Pedagogy
Description : Pedagogical Concept-DAG & Definition-Use Distance Verifier
Copyright   : (c) Nadia Yvette Chambers, 2026
License     : EUPL-1.2

@purpose
Verifies acyclic pedagogical concept ordering across documentation chapters
and enforces Crichton definition-use paragraph distance limits.

@behavior
Extracts defined and used concepts from Markdown frontmatter and inline directives,
detects forward-references without spiral annotations, and measures paragraph gaps.

@theory
Cognitive load theory (Sweller), concept maps, and Crichton Nota rule.

@contracts
Purity: Pure text analysis over documentation corpora.

@pattern
Topological concept accumulation and paragraph-indexed lookahead.

@example
verifyDocumentationCorpus defaultAuditThresholds "docs/" [("01-intro.md", ...)]
-}

module Gargamelle.Audit.Pedagogy
  ( verifyDocumentationCorpus
  ) where

import Data.List (find, isPrefixOf, sortOn)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import Gargamelle.Audit.Types
  ( AuditThresholds (..)
  , AuditViolation (..)
  , ViolationCategory (..)
  )

-- | Verify documentation corpus for pedagogical forward references and definition-use gaps.
verifyDocumentationCorpus :: AuditThresholds -> FilePath -> [(FilePath, Text)] -> [AuditViolation]
verifyDocumentationCorpus thresholds _ corpus =
  let orderedDocs = resolveReadingOrder corpus
      forwardRefViolations = checkForwardReferences orderedDocs
      gapViolations = concatMap (checkParagraphDefUseGap thresholds) orderedDocs
  in forwardRefViolations ++ gapViolations

resolveReadingOrder :: [(FilePath, Text)] -> [(FilePath, Text)]
resolveReadingOrder corpus =
  case find isIndex corpus of
    Just (_, indexText) ->
      let links = extractMarkdownLinks indexText
          matched = [ (fp, txt) | link <- links, (fp, txt) <- corpus, link `T.isInfixOf` T.pack fp ]
          unmatched = filter (\(fp, _) -> not (any (\(mFp, _) -> mFp == fp) matched)) corpus
      in matched ++ sortOn fst unmatched
    Nothing ->
      sortOn fst corpus
  where
    isIndex (fp, _) = "INDEX.md" `isPrefixOf` fp || "SUMMARY.md" `isPrefixOf` fp

extractMarkdownLinks :: Text -> [Text]
extractMarkdownLinks txt =
  let lns = T.lines txt
  in [ link | l <- lns, "(" `T.isInfixOf` l && ")" `T.isInfixOf` l
            , let (_, r) = T.breakOn "(" l
            , let link = fst (T.breakOn ")" (T.drop 1 r))
            , not (T.null link)
     ]

checkForwardReferences :: [(FilePath, Text)] -> [AuditViolation]
checkForwardReferences docs =
  let docConcepts = map (\(fp, txt) -> (fp, parseDocConcepts txt)) docs
      allDefinitions = [ (c, T.pack fp) | (fp, (defs, _, _)) <- docConcepts, c <- Set.toList defs ]
  in snd $ foldl (accumulateDoc allDefinitions) (Set.empty, []) docConcepts
  where
    accumulateDoc allDefs (definedSoFar, viols) (docPath, (defs, uses, spiral)) =
      let effectiveUses = Set.difference uses spiral
          missing = Set.difference effectiveUses (Set.union definedSoFar defs)
          newViols = [ AuditViolation
                         { avFilePath    = docPath
                         , avSymbol      = c
                         , avStartLine   = 1
                         , avEndLine     = 1
                         , avCategory    = PedagogicalForwardRef
                                             { conceptOrSymbol = c
                                             , usedInDoc       = T.pack docPath
                                             , definedInDoc    = lookup c allDefs
                                             }
                         , avRemediation = "Define concept earlier or annotate with <!-- @spiral: " <> c <> " -->"
                         }
                     | c <- Set.toList missing
                     ]
      in (Set.union definedSoFar defs, viols ++ newViols)

parseDocConcepts :: Text -> (Set Text, Set Text, Set Text)
parseDocConcepts txt =
  let lns = T.lines txt
      defs = concatMap (extractDirectiveValues "@defines:") lns
      uses = concatMap (extractDirectiveValues "@uses:") lns
      spiral = concatMap (extractDirectiveValues "@spiral:") lns
      (fmDefs, fmUses, fmSpiral) = extractFrontmatter lns
  in ( Set.fromList (defs ++ fmDefs)
     , Set.fromList (uses ++ fmUses)
     , Set.fromList (spiral ++ fmSpiral)
     )

extractDirectiveValues :: Text -> Text -> [Text]
extractDirectiveValues tag l =
  let s = T.strip l
  in if tag `T.isInfixOf` s
       then let (_, after) = T.breakOn tag s
                val = fst (T.breakOn "-->" (T.drop (T.length tag) after))
            in filter (not . T.null) $ map (cleanValue . T.strip) (T.split (== ',') val)
       else []

extractFrontmatter :: [Text] -> ([Text], [Text], [Text])
extractFrontmatter lns =
  case lns of
    ("---":rest) ->
      let (fmLines, _) = break (== "---") rest
          getVals key =
            case filter (\l -> (key <> ":") `T.isPrefixOf` T.strip l) fmLines of
              (l:_) ->
                let val = T.strip (T.drop (T.length key + 1) (T.strip l))
                    cleanVal = T.dropWhile (== '[') (T.dropWhileEnd (== ']') val)
                in filter (not . T.null) $ map (cleanValue . T.strip) (T.split (== ',') cleanVal)
              [] -> []
      in (getVals "defines", getVals "uses", getVals "spiral_uses")
    _ -> ([], [], [])

cleanValue :: Text -> Text
cleanValue t =
  T.filter (\c -> c /= '"' && c /= '\'' && c /= ' ' && c /= '[' && c /= ']') t

checkParagraphDefUseGap :: AuditThresholds -> (FilePath, Text) -> [AuditViolation]
checkParagraphDefUseGap thresholds (docPath, txt) =
  let paragraphs = splitParagraphs txt
      defMap = [ (c, idx) | (idx, p) <- zip [1..] paragraphs, c <- extractDefs p ]
      usesList = [ (c, idx) | (idx, p) <- zip [1..] paragraphs, c <- extractUses p ]
  in findGapViolations docPath (maxDefUseParagraphs thresholds) defMap usesList

findGapViolations :: FilePath -> Int -> [(Text, Int)] -> [(Text, Int)] -> [AuditViolation]
findGapViolations docPath maxGap defMap usesList =
  [ AuditViolation
      { avFilePath    = docPath
      , avSymbol      = sym
      , avStartLine   = uIdx
      , avEndLine     = uIdx
      , avCategory    = ExcessiveDefUseGap { symbolName = sym, paragraphGap = gap }
      , avRemediation = "Introduce definition within " <> T.pack (show maxGap) <> " paragraphs"
      }
  | (sym, uIdx) <- usesList
  , Just dIdx <- [lookup sym defMap]
  , let gap = dIdx - uIdx
  , gap > maxGap
  ]

splitParagraphs :: Text -> [Text]
splitParagraphs txt =
  let rawPara = T.splitOn "\n\n" txt
  in filter (not . T.null . T.strip) rawPara

extractDefs :: Text -> [Text]
extractDefs p =
  let lns = T.lines p
  in [ sym | l <- lns, "@def{" `T.isInfixOf` l
           , let (_, r) = T.breakOn "@def{" l
           , let sym = fst (T.breakOn "}" (T.drop 5 r))
           , not (T.null sym)
     ]

extractUses :: Text -> [Text]
extractUses p =
  let lns = T.lines p
  in [ sym | l <- lns, "@use{" `T.isInfixOf` l
           , not ("@spiral:" `T.isInfixOf` l)
           , let (_, r) = T.breakOn "@use{" l
           , let sym = fst (T.breakOn "}" (T.drop 5 r))
           , not (T.null sym)
     ]
