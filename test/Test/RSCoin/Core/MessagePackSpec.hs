{-# LANGUAGE ScopedTypeVariables #-}

module Test.RSCoin.Core.MessagePackSpec
       ( spec
       ) where

import           Data.Int                   (Int64)
import           Data.Maybe                 (fromJust)
import           Data.MessagePack           (MessagePack (..), pack, unpack)
import           Test.Hspec                 (Spec, describe)
import           Test.Hspec.QuickCheck      (prop)
import           Test.QuickCheck            (Arbitrary (arbitrary), Gen, scale,
                                             (===))

import qualified RSCoin.Core                as C

import           Test.RSCoin.Core.Arbitrary ()

makeSmall :: Gen a -> Gen a
makeSmall = scale f
  where
    -- f = (round . (sqrt :: Double -> Double) . realToFrac . (`div` 3))
    f 0 = 0
    f 1 = 1
    f 2 = 2
    f 3 = 3
    f 4 = 3
    f n
      | n < 0 = n
      | otherwise =
          (round . (sqrt :: Double -> Double) . realToFrac . (`div` 3)) n

newtype SmallLBlock =
    SmallLBlock C.LBlock
    deriving (MessagePack,Show,Eq)

instance Arbitrary SmallLBlock where
    arbitrary = SmallLBlock <$> makeSmall arbitrary

newtype SmallHBlock =
    SmallHBlock C.HBlock
    deriving (MessagePack,Show,Eq)

instance Arbitrary SmallHBlock where
    arbitrary = SmallHBlock <$> makeSmall arbitrary

newtype SmallNewPeriodData =
    SmallNewPeriodData C.NewPeriodData
    deriving (MessagePack,Show,Eq)

instance Arbitrary SmallNewPeriodData where
    arbitrary = SmallNewPeriodData <$> makeSmall arbitrary

newtype SmallTransaction =
    SmallTransaction C.Transaction
    deriving (MessagePack,Show,Eq)

instance Arbitrary SmallTransaction where
    arbitrary = SmallTransaction <$> makeSmall arbitrary

spec :: Spec
spec =
    describe "MessagePack" $ do
        describe "Identity Properties" $ do
            prop "Either Int Int" $
                \(a :: Either Int Int) -> a === mid a
            prop "Either Int (Either Int Int)" $
                \(a :: Either Int (Either Int Int)) -> a === mid a
            prop "Either (Either Int Int) Int" $
                \(a :: Either (Either Int Int) Int) -> a === mid a
            prop "Coin" $
                \(a :: C.Coin) -> a === mid a
            prop "Mintette" $
                \(a :: C.Mintette) -> a === mid a
            prop "Hash" $
                \(a :: C.Hash) -> a === mid a
            prop "Integer" $
                \(a :: Integer) -> a === mid a
            prop "Rational" $
                \(a :: Rational) -> a === mid a
            prop "Int64" $
                \(a :: Int64) -> a === mid a
            prop "Address" $
                \(a :: C.Address) -> a === mid a
            prop "NewPeriodData" $
                \(a :: SmallNewPeriodData) -> a === mid a
            prop "LBlock" $
                \(a :: SmallLBlock) -> a === mid a
            prop "HBlock" $
                \(a :: SmallHBlock) -> a === mid a
            prop "Transaction" $
                \(a :: SmallTransaction) -> a === mid a
            prop "CheckConfirmation" $
                \(a :: C.CheckConfirmation) -> a === mid a
            prop "ActionLogEntry" $
                \(a :: C.ActionLogEntry) -> a === mid a

mid :: MessagePack a => a -> a
mid = fromJust . unpack . pack
