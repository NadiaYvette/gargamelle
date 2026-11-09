{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module Gargamelle.Audit.WorkingMemory
  ( haskellCstAdapter
  , analyzeHaskellSource
  , detectSubstrateMode
  ) where

import Data.Char (isAlphaNum, isAsciiLower, isSpace)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import Gargamelle.Audit.Types
  ( AuditThresholds (..)
  , AuditViolation (..)
  , CstLangAdapter (..)
  , SubstrateMode (..)
  , ViolationCategory (..)
  )

-- | Haskell adapter conforming to 'CstLangAdapter'.
haskellCstAdapter :: CstLangAdapter
haskellCstAdapter = CstLangAdapter
  { claLanguageName = "Haskell"
  , claExtensions   = [".hs", ".lhs"]
  , claAnalyzeFile  = \thresh path src -> snd (analyzeHaskellSource thresh path src)
  }

-- | Analyze Haskell source code for parameter arity and working-memory peak violations.
analyzeHaskellSource
  :: AuditThresholds
  -> FilePath
  -> Text
  -> (SubstrateMode, [AuditViolation])
analyzeHaskellSource thresholds fp rawSrc =
  let mode = detectSubstrateMode rawSrc
      sanitized = sanitizeSource rawSrc
      rawLines = T.lines rawSrc
      cleanLines = T.lines sanitized
      indexedClean = zip [1 ..] cleanLines
      exports = extractExports sanitized

      arityViolations =
        if mode == SubstrateModule
          then []
          else checkParameterArity thresholds fp exports indexedClean

      wmViolations = checkWorkingMemory thresholds fp rawLines indexedClean
  in (mode, arityViolations ++ wmViolations)

-- | Detect whether a Haskell source module is in 'SubstrateModule' mode.
-- Triggered if:
--   1. The module name ends with @.Internal@ or contains @.Internal.@ or is @Internal@.
--   2. The file contains @{-# ANN module "audit:substrate" #-}@ (or substrate annotation).
detectSubstrateMode :: Text -> SubstrateMode
detectSubstrateMode rawSrc =
  if T.isInfixOf "ANN module \"audit:substrate\"" rawSrc
    then SubstrateModule
    else case extractModuleName rawSrc of
      Nothing -> StandardModule
      Just modName ->
        if modName == "Internal"
           || ".Internal" `T.isSuffixOf` modName
           || ".Internal." `T.isInfixOf` modName
          then SubstrateModule
          else StandardModule

-- | Extract module name from source.
extractModuleName :: Text -> Maybe Text
extractModuleName src =
  let ws = T.words (sanitizeSource src)
      afterModule = dropWhile (/= "module") ws
  in case afterModule of
    ("module" : name : _) -> Just (cleanModName name)
    _ -> Nothing
  where
    cleanModName = T.takeWhile (\c -> isAlphaNum c || c == '.' || c == '_')

-- | Replace comments and string/char literals with whitespace, preserving line and column offsets.
sanitizeSource :: Text -> Text
sanitizeSource txt = T.pack (go Normal (T.unpack txt))
  where
    go _ [] = []
    go Normal ('\n' : cs) = '\n' : go Normal cs
    go Normal ('"' : cs) = ' ' : go (InString False) cs
    go Normal ('\'' : cs) = ' ' : go (InChar False) cs
    go Normal ('{' : '-' : cs) = ' ' : ' ' : go (InBlockComment 1) cs
    go Normal ('-' : '-' : c : cs)
      | isCommentStartChar c = ' ' : ' ' : ' ' : go InLineComment cs
    go Normal ['-', '-'] = "  "
    go Normal (c : cs) = c : go Normal cs

    go InLineComment ('\n' : cs) = '\n' : go Normal cs
    go InLineComment (_ : cs) = ' ' : go InLineComment cs

    go (InBlockComment depth) ('\n' : cs) = '\n' : go (InBlockComment depth) cs
    go (InBlockComment depth) ('{' : '-' : cs) = ' ' : ' ' : go (InBlockComment (depth + 1)) cs
    go (InBlockComment depth) ('-' : '}' : cs)
      | depth <= 1 = ' ' : ' ' : go Normal cs
      | otherwise  = ' ' : ' ' : go (InBlockComment (depth - 1)) cs
    go (InBlockComment depth) (_ : cs) = ' ' : go (InBlockComment depth) cs

    go (InString _) ('\n' : cs) = '\n' : go Normal cs
    go (InString False) ('\\' : cs) = ' ' : go (InString True) cs
    go (InString True) (_ : cs) = ' ' : go (InString False) cs
    go (InString False) ('"' : cs) = ' ' : go Normal cs
    go (InString False) (_ : cs) = ' ' : go (InString False) cs

    go (InChar _) ('\n' : cs) = '\n' : go Normal cs
    go (InChar False) ('\\' : cs) = ' ' : go (InChar True) cs
    go (InChar True) (_ : cs) = ' ' : go (InChar False) cs
    go (InChar False) ('\'' : cs) = ' ' : go Normal cs
    go (InChar False) (_ : cs) = ' ' : go (InChar False) cs

    isCommentStartChar c = isSpace c || c == '\n' || isAlphaNum c || c `elem` ("([{'\":`~" :: String)

data LexerState
  = Normal
  | InLineComment
  | InBlockComment !Int
  | InString !Bool
  | InChar !Bool

-- | Extract exported symbols if an explicit export list is provided.
-- If no export list is present (e.g. @module Foo where@), returns 'Nothing',
-- denoting all top-level symbols are exported.
extractExports :: Text -> Maybe (Set Text)
extractExports sanitized =
  let t = T.stripStart sanitized
  in case findModuleHeader t of
    Nothing -> Nothing
    Just restAfterModule ->
      let trimmed = T.stripStart restAfterModule
      in if T.isPrefixOf "(" trimmed
           then Just (parseExportList (T.drop 1 trimmed))
           else Nothing
  where
    findModuleHeader s =
      case T.breakOn "module" s of
        (_, rest) | T.null rest -> Nothing
        (_, rest) ->
          let afterMod = T.drop 6 rest
              ws = T.words afterMod
          in case ws of
            [] -> Nothing
            (_modName : _) ->
              -- find start of export list or where
              let afterName = T.dropWhile (\c -> isAlphaNum c || c == '.' || c == '_' || isSpace c) afterMod
              in Just afterName

    parseExportList s =
      let inner = T.pack (takeParenDepth0 s)
          items = T.splitOn "," inner
          syms = concatMap extractSymbolsFromItem items
      in Set.fromList syms

    takeParenDepth0 str = go (0 :: Int) (T.unpack str)
      where
        go _ [] = ""
        go 0 (')' : _) = ""
        go d ('(' : cs) = '(' : go (d + 1) cs
        go d (')' : cs) = ')' : go (d - 1) cs
        go d (c : cs)   = c : go d cs

    extractSymbolsFromItem item =
      let clean = T.takeWhile (/= '(') (T.strip item)
          ws = T.words clean
      in case ws of
        ("pattern" : p : _) -> [p]
        ("type" : tp : _)   -> [tp]
        (x : _)             -> [x]
        []                  -> []

-- | Reserved keywords in Haskell.
haskellKeywords :: Set Text
haskellKeywords = Set.fromList
  [ "as", "case", "of", "class", "data", "default", "deriving"
  , "do", "forall", "foreign", "hiding", "if", "then", "else"
  , "import", "in", "infix", "infixl", "infixr", "instance"
  , "let", "module", "newtype", "qualified", "type", "where"
  , "stock", "anyclass", "via", "mdo", "rec"
  ]

-- | Check whether an identifier is a valid lowercase variable name.
isVarIdent :: Text -> Bool
isVarIdent t
  | T.null t = False
  | Set.member t haskellKeywords = False
  | otherwise =
      let h = T.head t
      in isAsciiLower h || (h == '_' && T.length t > 1)

-- | Extract all identifier tokens from a line of text.
tokenizeIdents :: Text -> [Text]
tokenizeIdents txt = filter (not . T.null) (T.split isNotIdentChar txt)
  where
    isNotIdentChar c = not (isAlphaNum c || c == '_' || c == '\'')

--------------------------------------------------------------------------------
-- Parameter Arity Gate
--------------------------------------------------------------------------------

checkParameterArity
  :: AuditThresholds
  -> FilePath
  -> Maybe (Set Text)
  -> [(Int, Text)]
  -> [AuditViolation]
checkParameterArity thresholds fp mExports indexedLines =
  let sigBlocks = findTopLevelSigs indexedLines
  in concatMap (evaluateSig thresholds fp mExports) sigBlocks

data SigBlock = SigBlock
  { sbStartLine :: !Int
  , sbEndLine   :: !Int
  , sbSymbols   :: ![Text]
  , sbTypeStr   :: !Text
  } deriving (Show)

findTopLevelSigs :: [(Int, Text)] -> [SigBlock]
findTopLevelSigs [] = []
findTopLevelSigs ((lineNo, line) : rest)
  -- Must start at column 0 (no leading space)
  | not (T.null line) && not (isSpace (T.head line)) && isTopLevelSigStart line =
      let (sigSyms, typeFirstPart) = splitSigLine line
          (continuation, remaining) = span isContinuationLine rest
          allTypeLines = typeFirstPart : map snd continuation
          lastLine = case continuation of
            [] -> lineNo
            cs -> fst (last cs)
          fullType = T.unwords (map T.strip allTypeLines)
          block = SigBlock
            { sbStartLine = lineNo
            , sbEndLine   = lastLine
            , sbSymbols   = sigSyms
            , sbTypeStr   = fullType
            }
      in block : findTopLevelSigs remaining
  | otherwise = findTopLevelSigs rest
  where
    isTopLevelSigStart l =
      case T.breakOn "::" l of
        (before, after) ->
          not (T.null after) && not (T.null (T.strip before)) && not (isKeywordDecl before)

    isKeywordDecl t =
      case T.words t of
        (w : _) -> Set.member w haskellKeywords
        [] -> False

    splitSigLine l =
      let (before, after) = T.breakOn "::" l
          syms = filter isVarIdent (map T.strip (T.splitOn "," before))
          typePart = T.drop 2 after
      in (syms, typePart)

    isContinuationLine (_, l) =
      T.null (T.strip l) || (not (T.null l) && isSpace (T.head l))

evaluateSig
  :: AuditThresholds
  -> FilePath
  -> Maybe (Set Text)
  -> SigBlock
  -> [AuditViolation]
evaluateSig thresholds fp mExports sb =
  let paramCount = countCurriedParams (sbTypeStr sb)
      limit = maxExplicitParams thresholds
  in if paramCount > limit
       then
         [ AuditViolation
             { avFilePath    = fp
             , avSymbol      = sym
             , avStartLine   = sbStartLine sb
             , avEndLine     = sbEndLine sb
             , avCategory    = ExcessiveParameterArity
                                 { paramCount  = paramCount
                                 , limitParams = limit
                                 }
             , avRemediation = "Bundle parameters into a Polytropos.Record or domain ADT."
             }
         | sym <- sbSymbols sb
         , isExported sym mExports
         ]
       else []
  where
    isExported _ Nothing = True
    isExported sym (Just expSet) = Set.member sym expSet

-- | Count explicit curried value parameters in a type signature string, ignoring typeclass constraints.
countCurriedParams :: Text -> Int
countCurriedParams typeStr =
  let withoutForall = stripForall (T.strip typeStr)
      withoutConstraints = stripConstraints withoutForall
  in countDepth0Arrows withoutConstraints
  where
    stripForall s
      | "forall " `T.isPrefixOf` s || "forall." `T.isPrefixOf` s =
          case T.breakOn "." s of
            (_, afterDot) | not (T.null afterDot) -> T.strip (T.drop 1 afterDot)
            _ -> s
      | otherwise = s

    stripConstraints s =
      case findDepth0DoubleArrow s of
        Nothing -> s
        Just afterArrow -> stripConstraints (T.strip afterArrow)

    findDepth0DoubleArrow s = go (0 :: Int) (0 :: Int) (T.unpack s)
      where
        go _ _ [] = Nothing
        go p b ('(' : cs) = go (p + 1) b cs
        go p b (')' : cs) = go (max 0 (p - 1)) b cs
        go p b ('[' : cs) = go p (b + 1) cs
        go p b (']' : cs) = go p (max 0 (b - 1)) cs
        go 0 0 ('=' : '>' : cs) = Just (T.pack cs)
        go 0 0 ('⇒' : cs)       = Just (T.pack cs)
        go p b (_ : cs)         = go p b cs

    countDepth0Arrows s = go (0 :: Int) (0 :: Int) (0 :: Int) (T.unpack s)
      where
        go _ _ acc [] = acc
        go p b acc ('(' : cs) = go (p + 1) b acc cs
        go p b acc (')' : cs) = go (max 0 (p - 1)) b acc cs
        go p b acc ('[' : cs) = go p (b + 1) acc cs
        go p b acc (']' : cs) = go p (max 0 (b - 1)) acc cs
        go 0 0 acc ('-' : '>' : cs) = go 0 0 (acc + 1) cs
        go 0 0 acc ('→' : cs)       = go 0 0 (acc + 1) cs
        go p b acc (_ : cs)         = go p b acc cs

--------------------------------------------------------------------------------
-- Working Memory Analyzer (|W(n)|)
--------------------------------------------------------------------------------

data DeclBlock = DeclBlock
  { dbSymbol    :: !Text
  , dbStartLine :: !Int
  , dbEndLine   :: !Int
  , dbLines     :: ![(Int, Text)]
  } deriving (Show)

checkWorkingMemory
  :: AuditThresholds
  -> FilePath
  -> [Text]
  -> [(Int, Text)]
  -> [AuditViolation]
checkWorkingMemory thresholds fp rawLines indexedClean =
  let decls = findTopLevelDecls rawLines indexedClean
  in concatMap (analyzeDecl thresholds fp) decls

findTopLevelDecls :: [Text] -> [(Int, Text)] -> [DeclBlock]
findTopLevelDecls _ [] = []
findTopLevelDecls rawLines indexedLines =
  let nonSigLines = filter (not . isSigLine . snd) indexedLines
  in groupDecls nonSigLines
  where
    isSigLine l =
      not (T.null l) && not (isSpace (T.head l)) && "::" `T.isInfixOf` l

    groupDecls [] = []
    groupDecls ((lineNo, line) : rest)
      | not (T.null line) && not (isSpace (T.head line)) && isFunctionStart line =
          let sym = extractDeclSymbol line
              (body, remaining) = span isIndentedOrBlank rest
              allLines = (lineNo, line) : body
              lastLine = case body of
                [] -> lineNo
                bs -> fst (last bs)
              -- If preceded by type signature for the same symbol, include it in start line
              actualStart = findSigStart sym lineNo
              decl = DeclBlock
                { dbSymbol    = sym
                , dbStartLine = actualStart
                , dbEndLine   = lastLine
                , dbLines     = allLines
                }
          in decl : groupDecls remaining
      | otherwise = groupDecls rest

    isFunctionStart l =
      let ws = T.words l
      in case ws of
        (w : _) -> isVarIdent w && not (Set.member w haskellKeywords)
        [] -> False

    extractDeclSymbol l =
      case T.words l of
        (w : _) -> w
        [] -> ""

    isIndentedOrBlank (_, l) =
      T.null (T.strip l) || (not (T.null l) && isSpace (T.head l))

    findSigStart sym eqLine =
      let candidateLine = eqLine - 1
      in if candidateLine >= 1 && candidateLine <= length rawLines
           then
             let prev = rawLines !! (candidateLine - 1)
             in if not (T.null prev) && not (isSpace (T.head prev)) && (sym <> " ::") `T.isPrefixOf` T.stripStart prev
                  then candidateLine
                  else eqLine
           else eqLine

data Binding = Binding
  { bId      :: !Int
  , bVar     :: !Text
  , bDefLine :: !Int
  , bLastUse :: !Int
  } deriving (Show)

analyzeDecl
  :: AuditThresholds
  -> FilePath
  -> DeclBlock
  -> [AuditViolation]
analyzeDecl thresholds fp decl =
  let spanLinesCount = dbEndLine decl - dbStartLine decl + 1
  in if spanLinesCount <= minLiveSpanLines thresholds
       then []
       else
         let bindings = extractLocalBindings decl
             liveLines = [dbStartLine decl .. dbEndLine decl]
             peak = foldl' (\mAcc l ->
                      let liveNow = countLiveAtLine l bindings
                      in max mAcc liveNow) 0 liveLines
             limit = maxLiveBindings thresholds
         in [ AuditViolation
                { avFilePath    = fp
                , avSymbol      = dbSymbol decl
                , avStartLine   = dbStartLine decl
                , avEndLine     = dbEndLine decl
                , avCategory    = WorkingMemoryPeakExceeded
                                    { peakCount  = peak
                                    , limitCount = limit
                                    , spanLines  = spanLinesCount
                                    }
                , avRemediation = "Decompose function or refactor local scopes to reduce simultaneous working-memory cognitive load below threshold."
                }
            | peak > limit
            ]
  where
    countLiveAtLine l = foldl' (\c b ->
      if bDefLine b <= l && l <= bLastUse b then c + 1 else c) 0

extractLocalBindings :: DeclBlock -> [Binding]
extractLocalBindings decl =
  let linesWithText = dbLines decl
      rawIntroductions = concatMap (extractIntroductionsFromLine (dbSymbol decl)) linesWithText
      -- Group introductions by var to resolve scope shadowing
      indexedIntro = zip [1 ..] rawIntroductions
  in map (computeBindingSpan linesWithText indexedIntro (dbEndLine decl)) indexedIntro

extractIntroductionsFromLine :: Text -> (Int, Text) -> [(Text, Int)]
extractIntroductionsFromLine fnName (lineNo, line) =
  let trimmed = T.strip line
  in if T.null trimmed
       then []
       else concat
         [ extractArgs lineNo trimmed
         , extractDoBinds lineNo trimmed
         , extractLetBinds lineNo trimmed
         , extractLambdaBinds lineNo trimmed
         , extractCaseBinds lineNo trimmed
         ]
  where
    -- 1. Function arguments from equation header: `fnName a b c = ...`
    extractArgs lNo t
      | (fnName <> " ") `T.isPrefixOf` t || fnName == t =
          let beforeEq = takeBeforeDelim '=' t
              ws = tokenizeIdents beforeEq
              args = case ws of
                (fn : rest) | fn == fnName -> filter isVarIdent rest
                _ -> []
          in [ (v, lNo) | v <- args ]
      | otherwise = []

    -- 2. Do-notation binds: `pat <- expr`
    extractDoBinds lNo t
      | "<-" `T.isInfixOf` t =
          let (lhs, _) = T.breakOn "<-" t
              vars = filter isVarIdent (tokenizeIdents lhs)
          in [ (v, lNo) | v <- vars ]
      | otherwise = []

    -- 3. Let / Where bindings: `let var = expr` or indented `var = expr`
    extractLetBinds lNo t
      | "let " `T.isInfixOf` t =
          let afterLet = snd (T.breakOn "let " t)
              beforeEq = takeBeforeDelim '=' (T.drop 4 afterLet)
              vars = filter isVarIdent (tokenizeIdents beforeEq)
          in [ (v, lNo) | v <- vars ]
      | otherwise = []

    -- 4. Lambda patterns: `\x y -> ...`
    extractLambdaBinds lNo t
      | "\\" `T.isInfixOf` t && "->" `T.isInfixOf` t =
          let afterSlash = snd (T.breakOn "\\" t)
              (lhs, _) = T.breakOn "->" (T.drop 1 afterSlash)
              vars = filter isVarIdent (tokenizeIdents lhs)
          in [ (v, lNo) | v <- vars ]
      | otherwise = []

    -- 5. Case branches: `Pat x y -> ...`
    extractCaseBinds lNo t
      | "->" `T.isInfixOf` t && not ("\\" `T.isInfixOf` t) && not ("::" `T.isInfixOf` t) =
          let (lhs, _) = T.breakOn "->" t
              beforeGuard = takeBeforeDelim '|' lhs
              vars = filter isVarIdent (tokenizeIdents beforeGuard)
          in [ (v, lNo) | v <- vars ]
      | otherwise = []

    takeBeforeDelim d t =
      case T.breakOn (T.singleton d) t of
        (before, _) -> before

computeBindingSpan
  :: [(Int, Text)]
  -> [(Int, (Text, Int))]
  -> Int
  -> (Int, (Text, Int))
  -> Binding
computeBindingSpan allLines allIntros declEnd (myId, (var, defLine)) =
  let nextDefLine = findNextDefLine
      candidateLines = [ lNo | (lNo, lText) <- allLines
                             , lNo >= defLine
                             , lNo < nextDefLine
                             , var `elem` tokenizeIdents lText
                             ]
      lastUse = case candidateLines of
        [] -> defLine
        ls -> maximum ls
  in Binding
       { bId      = myId
       , bVar     = var
       , bDefLine = defLine
       , bLastUse = max defLine lastUse
       }
  where
    findNextDefLine =
      let subsequent = [ otherDef | (otherId, (otherVar, otherDef)) <- allIntros
                                 , otherId > myId
                                 , otherVar == var
                                 , otherDef > defLine
                       ]
      in case subsequent of
        [] -> declEnd + 1
        (firstNext : _) -> firstNext
