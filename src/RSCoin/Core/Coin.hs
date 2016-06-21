-- | Functions related to Coin datatype

module RSCoin.Core.Coin
       ( onColor
       , sameColor
       , sumCoin
       , CoinsMap
       , coinsToList
       , coinsToMap
       , groupCoinsList
       , coinsMapConsistent
       , mergeCoinsMaps
       ) where

import           Control.Exception      (assert)
import           Data.Foldable          (foldr')
import           Data.List              (groupBy, sortBy)
import qualified Data.Map               as M
import           Data.Maybe             (fromJust)
import           Data.Ord               (comparing)

import           RSCoin.Core.Primitives (Coin (..), Color)


onColor :: Coin -> Coin -> Ordering
onColor = comparing getColor

sameColor :: Coin -> Coin -> Bool
sameColor a b = EQ == onColor a b

sumCoin :: [Coin] -> Coin
sumCoin [] = error "sumCoin called with empty coin list"
sumCoin xs@(c:_) = foldr' (+) c {getCoin = 0} xs

-- | Given a list of arbitrary coins, it sums the coins with the same
-- color and returns list of coins of distinct color sorted by the
-- color. Also deletes negative coins.
groupCoinsList :: [Coin] -> [Coin]
groupCoinsList coins =
    map sumCoin $
    filter (not . null) $
    groupBy sameColor $
    sortBy onColor $
    filter ((> 0) . getCoin)
    coins

type CoinsMap = M.Map Color Coin

-- | Translates a map of coins to the list, sorted by color
coinsToList :: CoinsMap -> [Coin]
coinsToList coinsMap = groupCoinsList $ M.elems coinsMap

-- | Translates a list of coins to the map
coinsToMap :: [Coin] -> CoinsMap
coinsToMap = M.fromList . map (\c -> (getColor c, c)) . groupCoinsList

-- | Checks a consistency of map from color to coin
coinsMapConsistent :: CoinsMap -> Bool
coinsMapConsistent coins = all keyValid $ M.keys coins
  where
    keyValid k = let coin = fromJust $ M.lookup k coins
                 in getColor coin == k

-- | Given a empty list of coin maps (map
mergeCoinsMaps :: [CoinsMap] -> CoinsMap
mergeCoinsMaps [] = M.empty
mergeCoinsMaps coinMaps =
    assert (all coinsMapConsistent coinMaps) $
    foldr1 (M.unionWith (+)) coinMaps
