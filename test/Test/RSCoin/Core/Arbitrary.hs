{-# LANGUAGE TemplateHaskell      #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE TypeSynonymInstances #-}

-- | Arbitrary instances for Core types.

module Test.RSCoin.Core.Arbitrary
       (
       ) where

import qualified Data.Data               as D
import           Data.DeriveTH
import           Data.List               (intersect)
import qualified Data.Map                as M
import qualified Data.Set                as S
import           Data.Text               (Text, pack)
import           Test.QuickCheck         (Arbitrary (arbitrary), Gen,
                                          NonNegative (..), choose, oneof)

import qualified RSCoin.Core           as C
import           RSCoin.Mintette.Error (MintetteError (..))
import           RSCoin.Notary.Error   (NotaryError (..))

instance Arbitrary C.Coin where
    arbitrary = do
        col <- arbitrary
        NonNegative coin <- arbitrary
        return $ C.Coin col coin

instance Arbitrary C.Mintette where
    arbitrary = C.Mintette <$> arbitrary <*> arbitrary

instance Arbitrary C.Explorer where
    arbitrary = C.Explorer <$> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary C.Hash where
    arbitrary = (C.hash :: C.Mintette -> C.Hash) <$> arbitrary

instance Arbitrary C.Address where
    arbitrary = C.Address <$> arbitrary

instance Arbitrary C.Transaction where
    arbitrary = C.Transaction <$> arbitrary <*> arbitrary

instance Arbitrary C.LBlock where
    arbitrary =
        C.LBlock <$> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary C.HBlock where
    arbitrary =
        C.HBlock <$> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary <*>
        pure M.empty

instance Arbitrary C.CheckConfirmation where
    arbitrary =
        C.CheckConfirmation <$> arbitrary <*> arbitrary <*> arbitrary <*>
        (abs <$> arbitrary)

instance Arbitrary C.CommitAcknowledgment where
    arbitrary = C.CommitAcknowledgment <$> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary C.Signature where
    arbitrary = C.sign <$> arbitrary <*> (arbitrary :: Gen String)

instance Arbitrary C.TxStrategy where
    arbitrary = oneof [ pure C.DefaultStrategy
                      , uncurry C.MOfNStrategy <$> gen']
      where gen' = do ls <- arbitrary
                      flip (,) ls <$> choose (1, length ls)

instance Arbitrary C.NewPeriodData where
    arbitrary =
        C.NewPeriodData
        <$> arbitrary
        <*> arbitrary
        <*> arbitrary
        <*> arbitrary
        <*> arbitrary

instance Arbitrary C.AllocationAddress where
    arbitrary = oneof [ C.TrustAlloc <$> arbitrary
                      , C.UserAlloc <$> arbitrary
                      ]

instance Arbitrary C.PartyAddress where
    arbitrary = oneof [ C.TrustParty <$> arbitrary <*> arbitrary
                      , C.UserParty <$> arbitrary
                      ]

instance Arbitrary C.AllocationStrategy where
    arbitrary = C.AllocationStrategy <$> arbitrary <*> arbitrary

instance Arbitrary C.ActionLogEntry where
    arbitrary = oneof [ C.QueryEntry <$> arbitrary
                      , C.CommitEntry <$> arbitrary <*> arbitrary
                      , C.CloseEpochEntry <$> arbitrary
                      ]

{-instance Arbitrary [(C.Color, C.Coin)] where
    arbitrary = do
        list <- arbitrary :: Gen [(C.Color, NonNegative Rational)]
        return $ map (\(col,NonNegative rt) -> (col, C.Coin col rt)) list

instance Arbitrary C.CoinsMap where
    arbitrary = do
        list <- arbitrary
        return $ M.fromListWith (+) list

--this instance isn't working at the moment, causes an error.
-}


{- Section for errors. Created after some crazy ResultMismatchError bug. -}
instance Arbitrary Text where
    arbitrary = pack <$> arbitrary

derive makeArbitrary ''MintetteError
derive makeArbitrary ''NotaryError
