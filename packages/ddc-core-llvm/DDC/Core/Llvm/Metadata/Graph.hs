{-# LANGUAGE TupleSections, FlexibleInstances #-}
-- Manipulate graphs for metadata generation
--  WARNING: everything in here is REALLY SLOW
--
module DDC.Core.Llvm.Metadata.Graph
       ( -- * Binary Relations
         Rel
       , fromList, toList
       , allR, differenceR, unionR, composeR, transitiveR
       , transClosure

         -- * Graphs
       , UG(..)
       , DG(..)
       , transClosureDG, orientation
       , transOrientation,    minOrientation
       , partitionDG

         -- * Trees
       , Tree(..)
       , sources, anchor )
where
import Data.List          hiding (partition)
import Data.Ord
import Data.Tuple
import Data.Maybe
import Control.Monad


-- Binary relations -----------------------------------------------------------
-- | A binary relation.
type Rel a = a -> a -> Bool
type Dom a = [a]


-- | Convert a relation.
toList :: Dom a -> Rel a -> [(a, a)]
toList dom r = [ (x, y) | x <- dom, y <- dom, r x y ]


-- | Convert a list to a relation.
fromList :: Eq a => [(a, a)] -> Rel a
fromList s = \x y -> (x,y) `elem` s


-- | Get the size of a a relation.
size :: Dom a -> Rel a -> Int
size d r = length $ toList d r


-- | The universal negative relation.
--   All members of the domain are not related.
allR :: Eq a => Rel a
allR = (/=)


-- | Fifference of two relations.
differenceR :: Rel a -> Rel a -> Rel a
differenceR     f g = \x y -> f x y && not (g x y)


-- | Union two relations.
unionR :: Rel a -> Rel a -> Rel a
unionR          f g = \x y -> f x y || g x y


-- | Compose two relations.
composeR :: Dom a -> Rel a -> Rel a -> Rel a
composeR dom f g = \x y -> or [ f x z && g z y | z <- dom ]


-- | Check whether a relation is transitive.
transitiveR :: Dom a -> Rel a -> Bool
transitiveR dom r
 = and [ not (r x y  && r y z && not (r x z)) 
       | x <- dom, y <- dom, z <- dom ]


-- | Find the transitive closure of a binary relation
--      using Floyd-Warshall algorithm
transClosure :: (Eq a) => Dom a -> Rel a -> Rel a
transClosure dom r = fromList $ step dom $ toList dom r
    where step [] es     = es
          step (_:xs) es = step xs 
                          $ nub (es ++ [(a, d) 
                                | (a, b) <- es
                                , (c, d) <- es
                                , b == c])


-- | Get the size of the transitive closure of a relation.
transCloSize :: (Eq a) => Dom a -> Rel a -> Int
transCloSize d r = size d $ transClosure d r


-- Graphs ---------------------------------------------------------------------
-- | An undirected graph.
newtype UG  a = UG (Dom a, Rel a)

-- | A directed graph.
newtype DG  a = DG (Dom a, Rel a)

instance Show a => Show (UG a) where
  show (UG (d,r)) = "UG (" ++ (show d) ++ ", " ++ (show $ toList d r) ++ ")"

instance Show a => Show (DG a) where
  show (DG (d,r)) = "DG (" ++ (show d) ++ ", " ++ (show $ toList d r) ++ ")"


-- | Give a random orientation of an undirected graph.
orientation :: Eq a => UG a -> DG a
orientation (UG (d,g)) = DG (d,g)


-- | Compute the transitive closure of a directed graph.
transClosureDG :: (Eq a) => DG a -> DG a
transClosureDG (DG (d,g)) = DG (d, transClosure d g)


-- | Find the transitive orientation of an undirected graph if one exists
--    TODO implement linear time algorithm (this is the whole point of
--         finding the transitive orientation before bruteforcing for
--         the minimum orientation!)
--
transOrientation :: Eq a => UG a -> Maybe (DG a)
transOrientation (UG (d,g))
 = case toList d g of
        [] -> Just (DG (d,g))
        edges 
          -> let  -- Treat G as a directed graph. For all subsets S of A (set of arcs),
                  --   reverse the direction of all arcs in S and check if the result
                  --   is transitive.
                  combo k      = filter ((k==) . length) $ subsequences edges
                  choices      = concatMap combo [1..length d]
                  choose c     = g `differenceR` fromList c
                                   `unionR`      fromList (map swap c)
              in  liftM DG $ liftM (d,) $ find (transitiveR d) $ map choose choices


-- | Find the orientation with the smallest transitive closure
minOrientation :: (Show a, Eq a) => UG a -> DG a
minOrientation ug = fromMaybe (minOrientation' ug) (transOrientation ug)

minOrientation' :: (Show a, Eq a) => UG a -> DG a
minOrientation' (UG (d, g))
 = case toList d g of
        [] -> DG (d,g)
        edges 
          -> let  combo k   = filter ((k==) . length) $ subsequences edges
                  choices   = concatMap combo [1..length d]
                  choose c  = g `differenceR` fromList c
                                `unionR`      fromList (map swap c)
                  minTransClo = head $ sortBy (comparing $ transCloSize d) 
                                     $ map choose choices
              in  DG (d, minTransClo)


-- Trees ----------------------------------------------------------------------
-- | An inverted tree (with edges going from child to parent)
newtype Tree a = Tree (Dom a, Rel a)

instance Show a => Show (Tree a) where
  show (Tree (d,r)) = "tree (" ++ (show d) ++ ", " ++ (show $ toList d r) ++ ")"


-- | A relation is an (inverted) tree if each node has at most one outgoing arc
isTree :: Dom a -> Rel a -> Bool
isTree dom r 
  = let neighbours x = filter (r x) dom 
    in  all ((<=1) . length . neighbours) dom


-- | Get the sources of a tree.
sources :: Eq a => a -> Tree a -> [a]
sources x (Tree (d, r)) = [y | y <- d, r y x]


-- | Partition a DG into the minimum set of (directed) trees
--    rank the partitionings by the number of partitions for now
--   
partitionDG :: Eq a => DG a -> [Tree a]
partitionDG (DG (d,g))
 = let mkGraph  g' nodes = (nodes, fromList [ (x,y) | x <- nodes, y <- nodes, g' x y ])
   in map Tree $ fromMaybe (error "partitionDG: no partition found!") 
               $ find (all $ uncurry isTree) 
               $ map (map (mkGraph g)) 
               $ sortBy (comparing (aliasingAmount g))
               $ partitionings d


-- | A partitioning of a tree.
type Partitioning a = [SubList a]
type SubList a      = [a]


-- | Calculate the aliasing induced by a set of trees
--      this includes aliasing within each of the trees
--      and aliasing among trees
--   TODO - come up with a more efficient to compute measure
--
aliasingAmount :: Eq a => Rel a -> Partitioning a -> Int
aliasingAmount g p
 = (outerAliasing $ map length p) + (sum $ map innerAliasing p)
    where innerAliasing t = length $ toList t $ transClosure t g
          outerAliasing (l:ls) = l * (sum ls) + outerAliasing ls
          outerAliasing []     = 0


-- | Generate all possible partitions of a list
--    by nondeterministically decide which sublist to add an element to.
partitionings :: Eq a => [a] -> [Partitioning a]
partitionings []     = [[]]
partitionings (x:xs) = concatMap (nondetPut x) $ partitionings xs
  where nondetPut :: a -> Partitioning a -> [Partitioning a]
        nondetPut y []     = [ [[y]] ]
        nondetPut y (l:ls) = let putHere  = (y:l):ls
                                 putLater = map (l:) $ nondetPut y ls
                              in putHere:putLater
                 
        
-- | Enroot a tree with the given root.
anchor :: Eq a => a -> Tree a -> Tree a
anchor root (Tree (d,g))
  = let leaves = filter (null . flip filter d . g) d
        arcs   = map (, root) leaves
    in  Tree (root:d, g `unionR` fromList arcs)