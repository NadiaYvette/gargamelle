{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : Gargamelle.Audit.ApiGraph
Description : Bipartite API Exploration Graph Verifier
Copyright   : (c) Nadia Yvette Chambers, 2026
License     : EUPL-1.2

@purpose
Constructs the bipartite reachability graph between domain types and functions
to detect orphaned or excessive-depth helper types.

@behavior
Extracts exported types and function signatures, establishes reachability
from primary domain types, and flags types exceeding maxApiHops distance.

@theory
Stylos & Myers / Robillard API exploration graph and cognitive diameter bounds.

@contracts
Purity: Deterministic and total graph traversal.

@pattern
Adjacency map breadth-first search (BFS).

@example
verifyApiExplorationGraph defaultAuditThresholds StandardModule "src/Foo.hs" src
-}

module Gargamelle.Audit.ApiGraph
  ( verifyApiExplorationGraph
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import Gargamelle.Audit.Types
  ( AuditThresholds (..)
  , AuditViolation (..)
  , SubstrateMode (..)
  , ViolationCategory (..)
  )

-- | Verify API reachability diameter from primary domain types.
verifyApiExplorationGraph :: AuditThresholds -> SubstrateMode -> FilePath -> Text -> [AuditViolation]
verifyApiExplorationGraph _ SubstrateModule _ _ = []
verifyApiExplorationGraph thresholds StandardModule path src =
  let lns = T.lines src
      (typeDecls, funcDecls) = parseDecls lns
      allTypes = Set.fromList [ t | (t, _, _) <- typeDecls ]
      primaryTypes = identifyPrimaryTypes typeDecls funcDecls (T.pack path)
      graph = buildReachabilityGraph allTypes funcDecls
      helperTypes = Set.toList (Set.difference allTypes (Set.fromList primaryTypes))
  in [ AuditViolation
        { avFilePath    = path
        , avSymbol      = h
        , avStartLine   = lineNum
        , avEndLine     = lineNum
        , avCategory    = ApiReachabilityExceeded
                            { helperType   = h
                            , measuredHops = d
                            , maxHops      = maxApiHops thresholds
                            }
        , avRemediation = "Provide direct entrypoint constructor or conversion function from primary domain type"
        }
     | (h, _, lineNum) <- [ decl | decl@(t, _, _) <- typeDecls, t `elem` helperTypes ]
     , let d = shortestDistance primaryTypes h graph
     , maybe True (> maxApiHops thresholds) d
     ]

parseDecls :: [Text] -> ([(Text, Bool, Int)], [(Text, [Text], Text)])
parseDecls lns = go 1 [] [] lns
  where
    go _ typeAcc funcAcc [] = (reverse typeAcc, reverse funcAcc)
    go lineNum typeAcc funcAcc (l:rest)
      | isTypeDecl l =
          let (tName, hasPrimary) = extractTypeName l
          in go (lineNum + 1) ((tName, hasPrimary, lineNum) : typeAcc) funcAcc rest
      | isFuncSig l =
          let (fName, inTypes, outType) = extractSignature l
          in go (lineNum + 1) typeAcc ((fName, inTypes, outType) : funcAcc) rest
      | otherwise =
          go (lineNum + 1) typeAcc funcAcc rest

    isTypeDecl l =
      let s = T.stripStart l
      in ("data " `T.isPrefixOf` s || "newtype " `T.isPrefixOf` s || "type " `T.isPrefixOf` s)
         && not ("deriving" `T.isPrefixOf` s)

    extractTypeName l =
      let s = T.stripStart l
          tokens = T.words s
          rawName = case tokens of
            (_:name:_) -> fst (T.breakOn "=" (fst (T.breakOn " " name)))
            _          -> "Type"
          hasPrimary = "@primary_type" `T.isInfixOf` l || "Primary" `T.isInfixOf` rawName
      in (rawName, hasPrimary)

    isFuncSig l =
      let s = T.stripStart l
      in "::" `T.isInfixOf` s
         && not ("data " `T.isPrefixOf` s)
         && not ("newtype " `T.isPrefixOf` s)
         && not ("type " `T.isPrefixOf` s)
         && not ("--" `T.isPrefixOf` s)

    extractSignature l =
      let (namePart, sigPart) = T.breakOn "::" l
          fName = T.strip namePart
          sigTokens = filter (not . T.null) $ map cleanToken (T.words (T.drop 2 sigPart))
          (inParts, outPart) = if null sigTokens
            then ([], "")
            else (init sigTokens, last sigTokens)
      in (fName, inParts, outPart)

    cleanToken t =
      T.filter (\c -> c /= '(' && c /= ')' && c /= ',' && c /= '-') t

identifyPrimaryTypes :: [(Text, Bool, Int)] -> [(Text, [Text], Text)] -> Text -> [Text]
identifyPrimaryTypes types _ path =
  let primAnnotated = [ t | (t, isPrim, _) <- types, isPrim ]
  in if not (null primAnnotated)
       then primAnnotated
       else
         let cleanTypes = [ t | (t, _, _) <- types ]
             pathMatched = filter (\t -> t `T.isInfixOf` path) cleanTypes
         in if not (null pathMatched)
              then pathMatched
              else case cleanTypes of
                     (firstType:_) -> [firstType]
                     []            -> []

buildReachabilityGraph :: Set Text -> [(Text, [Text], Text)] -> Map Text (Set Text)
buildReachabilityGraph allTypes funcs =
  foldl addFuncEdges Map.empty funcs
  where
    addFuncEdges m (_, inT, outT) =
      let knownIn = filter (`Set.member` allTypes) inT
          knownOut = [outT | Set.member outT allTypes]
          edges = [ (u, v) | u <- knownIn, v <- knownOut, u /= v ]
                  ++ [ (v, u) | u <- knownIn, v <- knownOut, u /= v ]
                  ++ [ (u, v) | u <- knownIn, v <- knownIn, u /= v ]
      in foldl (\acc (u, v) -> Map.insertWith Set.union u (Set.singleton v) acc) m edges

shortestDistance :: [Text] -> Text -> Map Text (Set Text) -> Maybe Int
shortestDistance starts target graph
  | target `elem` starts = Just 0
  | otherwise = bfs (Set.fromList starts) [(s, 0) | s <- starts]
  where
    bfs _ [] = Nothing
    bfs visited ((curr, dist):queue) =
      let neighbors = maybe Set.empty id (Map.lookup curr graph)
      in if Set.member target neighbors
           then Just (dist + 1)
           else
             let newVisited = Set.union visited neighbors
                 unvisited = Set.difference neighbors visited
                 nextQueue = queue ++ [(n, dist + 1) | n <- Set.toList unvisited]
             in bfs newVisited nextQueue
