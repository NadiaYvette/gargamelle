{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : Gargamelle.Audit.Scent
Description : Lexical Information-Scent Engine & Tautological Docstring Rejector
Copyright   : (c) Nadia Yvette Chambers, 2026
License     : EUPL-1.2

@purpose
Provides identifier splitting, morphological stem normalization, and novel-stem
ratio computation for detecting low-information tautological docstrings.

@behavior
Splits camelCase, PascalCase, snake_case, and numerical/prime suffixes, strips
Haskell and English stopwords, normalizes inflectional endings, and computes
set-difference ratios between docstrings and signatures.

@theory
Information-scent theory (Pirolli & Card) and Maalej-Robillard docstring taxonomy.

@contracts
Purity: All functions are deterministic and total.

@pattern
Lexical tokenization followed by set-theoretic divergence scoring.

@example
computeNovelStemRatio "rcast" "SubRow s t => Record f t -> Record f s" "Casts a record from t to s."
-- Returns < 0.5 (Tautological)
-}

module Gargamelle.Audit.Scent
  ( splitIdentifier
  , normalizeStem
  , computeNovelStemRatio
  , isStopword
  ) where

import Data.Char (isAlpha, isAlphaNum, isDigit, isLower, isPunctuation, isUpper)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

-- | Splits camelCase, PascalCase, snake_case, and prime/number suffixes.
-- E.g.:
--   splitIdentifier "rcastRecord2" == ["rcast", "record"]
--   splitIdentifier "checkLiquidSubtypingZ3" == ["check", "liquid", "subtyping", "z3"]
splitIdentifier :: Text -> [Text]
splitIdentifier txt =
  let cleanTxt = T.dropWhileEnd (\c -> isDigit c || c == '\'') txt
      chunks = T.split (== '_') cleanTxt
  in filter (not . T.null) $ concatMap splitCase chunks
  where
    splitCase :: Text -> [Text]
    splitCase t
      | T.null t = []
      | otherwise =
          let s = T.unpack t
              parts = breakTransitions s
          in map (T.toLower . T.pack) parts

    breakTransitions :: String -> [String]
    breakTransitions [] = []
    breakTransitions [c]
      | isAlphaNum c = [[c]]
      | otherwise = []
    breakTransitions (c1:c2:rest)
      -- lowercase to uppercase transition (e.g. 't' 'R' in rcastRecord)
      | isLower c1 && isUpper c2 =
          [c1] : breakTransitions (c2:rest)
      -- consecutive uppercase followed by lowercase (e.g. 'N' 'P' 'a' in JSONParser -> JSON, Parser)
      | isUpper c1 && isUpper c2 && not (null rest) && isLower (case rest of (r:_) -> r; [] -> ' ') =
          [c1] : breakTransitions (c2:rest)
      | otherwise =
          case breakTransitions (c2:rest) of
            [] -> [[c1]]
            (hd:tl) -> (c1:hd) : tl

-- | Lowercases, strips punctuation, removes common English/Haskell stopwords,
-- and strips standard inflectional suffixes (-ing, -ed, -es, -s, -tion, -ly)
-- for tokens of length >= 5.
normalizeStem :: Text -> Text
normalizeStem t =
  let stripped = T.filter (\c -> isAlpha c || isDigit c) (T.toLower t)
  in if isStopword stripped
       then ""
       else stripInflection stripped

isStopword :: Text -> Bool
isStopword w = Set.member w stopwords
  where
    stopwords :: Set Text
    stopwords = Set.fromList
      [ "the", "a", "an", "to", "from", "of", "in", "for", "with"
      , "by", "on", "is", "are", "returns", "takes", "given", "function"
      , "method", "value", "type", "data", "pure", "io", "and", "or", "as"
      , "at", "it", "this", "that", "be", "was", "will", "all", "any"
      ]

stripInflection :: Text -> Text
stripInflection w
  | T.length w < 5 = w
  | "tion" `T.isSuffixOf` w && T.length w >= 6 = T.dropEnd 4 w
  | "ing" `T.isSuffixOf` w && T.length w >= 5 = T.dropEnd 3 w
  | "ed" `T.isSuffixOf` w && T.length w >= 5 = T.dropEnd 2 w
  | "es" `T.isSuffixOf` w && T.length w >= 5 = T.dropEnd 2 w
  | "ly" `T.isSuffixOf` w && T.length w >= 5 = T.dropEnd 2 w
  | "s" `T.isSuffixOf` w && T.length w >= 5 = T.dropEnd 1 w
  | otherwise = w

-- | Tokenize a signature or sentence into candidate stems.
tokenizeText :: Text -> [Text]
tokenizeText t =
  let wordsList = T.words (T.map replacePunct t)
  in concatMap splitIdentifier wordsList
  where
    replacePunct c
      | isPunctuation c && c /= '_' = ' '
      | otherwise = c

-- | NovelStemRatio = |S_doc \ S_sig| / max(1, |S_sig|)
-- If docstring is empty, return 0.0.
computeNovelStemRatio :: Text -> Text -> Text -> Double
computeNovelStemRatio ident typeSig docstring =
  let cleanDoc = stripSlotTags docstring
      sigTokens = splitIdentifier ident ++ tokenizeText typeSig
      docTokens = tokenizeText cleanDoc
      sigStems = Set.fromList $ filter (not . T.null) $ map normalizeStem sigTokens
      docStems = Set.fromList $ filter (not . T.null) $ map normalizeStem docTokens
  in if Set.null docStems
       then 0.0
       else
         let novel = Set.difference docStems sigStems
             novelCount = Set.size novel
             sigCount = max 1 (Set.size sigStems)
         in fromIntegral novelCount / fromIntegral sigCount
  where
    stripSlotTags txt =
      let lns = T.lines txt
          notTag l = not ("@" `T.isPrefixOf` T.stripStart l)
      in T.unwords (filter notTag lns)
