{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Gargamelle.Sheaf.Complex
  ( -- * Cell Complex
    CellComplex(..)
  , emptyComplex
  , fromEdges
  , addVertex
  , addEdge
    -- * Cells & Poset Structure
  , Cell(..)
  , cellDimension
  , cellFaces
  , isFaceOf
  , Orientation(..)
  , orientationSign
  , incidenceSign
    -- * Complex Queries
  , incidentEdges
  , star
  , boundary
  , numVertices
  , numEdges
  , eulerCharacteristic
  ) where

import Data.List (nub)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map

-- | A finite 1-dimensional cell complex (graph complex) G = (V, E).
-- 0-cells represent component spaces/loci, and 1-cells represent interface boundaries.
data CellComplex vId eId = CellComplex
  { vertices :: [vId]
  , edges    :: Map eId (vId, vId) -- ^ Map from edge ID to (source, target)
  } deriving (Eq, Show)

-- | Orientation of an incident edge relative to a vertex.
data Orientation
  = Forward   -- ^ Directed away from the vertex (vertex is source: sign -1 in boundary)
  | Backward  -- ^ Directed into the vertex (vertex is target: sign +1 in boundary)
  deriving (Eq, Ord, Show)

-- | Numeric homological sign for an orientation.
orientationSign :: Orientation -> Int
orientationSign = \case
  Forward  -> -1
  Backward -> 1

-- | The cells of a 1-dimensional cell complex, forming a graded face poset.
data Cell vId eId
  = Cell0 vId  -- ^ 0-cell (vertex)
  | Cell1 eId  -- ^ 1-cell (edge)
  deriving (Eq, Ord, Show)

-- | Dimension of a cell in the complex.
cellDimension :: Cell vId eId -> Int
cellDimension = \case
  Cell0 _ -> 0
  Cell1 _ -> 1

-- | Empty cell complex.
emptyComplex :: CellComplex vId eId
emptyComplex = CellComplex
  { vertices = []
  , edges    = Map.empty
  }

-- | Construct a cell complex from a list of directed edges (eId, source, target).
-- Vertices are automatically collected and deduplicated.
fromEdges :: forall vId eId. (Eq vId, Ord eId) => [(eId, vId, vId)] -> CellComplex vId eId
fromEdges edgeList = CellComplex
  { vertices = nub [ v | (_, u, w) <- edgeList, v <- [u, w] ]
  , edges    = Map.fromList [ (e, (u, w)) | (e, u, w) <- edgeList ]
  }

-- | Add a vertex to the cell complex if not already present.
addVertex :: (Eq vId) => vId -> CellComplex vId eId -> CellComplex vId eId
addVertex v complex
  | v `elem` vertices complex = complex
  | otherwise = complex { vertices = v : vertices complex }

-- | Add an edge and ensure its endpoints are in the vertex set.
addEdge :: (Ord eId, Eq vId) => eId -> vId -> vId -> CellComplex vId eId -> CellComplex vId eId
addEdge e u w complex = complex
  { vertices = nub (u : w : vertices complex)
  , edges    = Map.insert e (u, w) (edges complex)
  }

-- | Boundary of a 1-cell (source, target).
boundary :: (Ord eId) => CellComplex vId eId -> eId -> Maybe (vId, vId)
boundary complex e = Map.lookup e (edges complex)

-- | Incident edges for a given vertex, including orientation and adjacent vertex.
incidentEdges :: (Eq vId) => CellComplex vId eId -> vId -> [(eId, Orientation, vId)]
incidentEdges complex v =
  [ (e, orient, other)
  | (e, (u, w)) <- Map.toList (edges complex)
  , (orient, other) <-
      let isSrc = u == v
          isTgt = w == v
      in case (isSrc, isTgt) of
           (True, False) -> [(Forward, w)]
           (False, True) -> [(Backward, u)]
           (True, True)  -> [(Forward, w), (Backward, u)]
           (False, False)-> []
  ]

-- | Star (co-faces) of a vertex: all edges incident to v.
star :: (Eq vId) => CellComplex vId eId -> vId -> [eId]
star complex v = [ e | (e, _, _) <- incidentEdges complex v ]

-- | Faces of a cell in the cell complex.
cellFaces :: (Ord eId) => CellComplex vId eId -> Cell vId eId -> [Cell vId eId]
cellFaces complex = \case
  Cell0 v -> [Cell0 v]
  Cell1 e -> case boundary complex e of
    Nothing     -> [Cell1 e]
    Just (u, w) -> [Cell1 e, Cell0 u, Cell0 w]

-- | Partial order predicate: checks whether sigma is a face of tau (sigma <= tau).
isFaceOf :: (Ord eId, Eq vId) => CellComplex vId eId -> Cell vId eId -> Cell vId eId -> Bool
isFaceOf complex sigma tau = case (sigma, tau) of
  (Cell0 u, Cell0 v) -> u == v
  (Cell1 a, Cell1 b) -> a == b
  (Cell0 u, Cell1 e) -> case boundary complex e of
    Just (src, tgt) -> u == src || u == tgt
    Nothing         -> False
  (Cell1 _, Cell0 _) -> False

-- | Homological incidence sign [e : v] of vertex v in edge e.
-- Returns -1 if v is source, +1 if v is target, 0 if not incident.
incidenceSign :: (Ord eId, Eq vId) => CellComplex vId eId -> eId -> vId -> Int
incidenceSign complex e v = case boundary complex e of
  Just (src, tgt) -> case (v == src, v == tgt) of
    (True, False) -> -1
    (False, True) -> 1
    (True, True)  -> 0 -- Self-loop cancels in standard homology
    (False, False)-> 0
  Nothing -> 0

-- | Count of 0-cells.
numVertices :: CellComplex vId eId -> Int
numVertices = length . vertices

-- | Count of 1-cells.
numEdges :: CellComplex vId eId -> Int
numEdges = Map.size . edges

-- | Euler characteristic chi = |V| - |E| = beta_0 - beta_1.
eulerCharacteristic :: CellComplex vId eId -> Int
eulerCharacteristic c = numVertices c - numEdges c
