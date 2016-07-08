{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies    #-}

-- | Wrap Storage into AcidState.

module RSCoin.Notary.AcidState
       ( RSCoinNotaryState

         -- * acid-state query and update data types
       , GetSignatures (..)
       , AddSignature       (..)
       , AnnounceNewPeriods (..)
       , GetPeriodId (..)
       , PollTransactions (..)
       , AcquireSignatures (..)

         -- * Bracket functions
       , openState
       , openMemState
       , closeState
       ) where

import           Data.Acid             (AcidState, closeAcidState, makeAcidic,
                                        openLocalStateFrom)
import           Data.Acid.Memory      (openMemoryState)
import           Data.SafeCopy         (base, deriveSafeCopy)

import           RSCoin.Notary.Storage (Storage)
import qualified RSCoin.Notary.Storage as S

type RSCoinNotaryState = AcidState Storage

$(deriveSafeCopy 0 'base ''Storage)

openState :: FilePath -> IO RSCoinNotaryState
openState fp = openLocalStateFrom fp S.emptyNotaryStorage

openMemState :: IO RSCoinNotaryState
openMemState = openMemoryState S.emptyNotaryStorage

closeState :: RSCoinNotaryState -> IO ()
closeState = closeAcidState

$(makeAcidic ''Storage
             [ 'S.addSignature
             , 'S.getSignatures
             , 'S.announceNewPeriods
             , 'S.getPeriodId
             , 'S.pollTransactions
             , 'S.acquireSignatures
             ])
