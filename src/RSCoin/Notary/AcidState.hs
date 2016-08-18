{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies    #-}

-- | Wrap Storage into AcidState.

module RSCoin.Notary.AcidState
       ( RSCoinNotaryState

         -- * acid-state query and update data types
       , AcquireSignatures (..)
       , AddSignedTransaction (..)
       , AllocateMSAddress (..)
       , AnnounceNewPeriods (..)
       , GetPeriodId (..)
       , GetSignatures (..)
       , PollTransactions (..)
       , QueryAllMSAdresses (..)
       , QueryCompleteMSAdresses (..)
       , QueryMyMSRequests (..)
       , RemoveCompleteMSAddresses (..)

         -- * Bracket functions
       , openState
       , openMemState
       , closeState
       ) where

import           Data.Acid             (AcidState, closeAcidState, makeAcidic,
                                        openLocalStateFrom)
import           Data.Acid.Memory      (openMemoryState)
import           Data.SafeCopy         (base, deriveSafeCopy)

import           RSCoin.Core           (PublicKey)
import           RSCoin.Notary.Storage (Storage (..))
import qualified RSCoin.Notary.Storage as S

type RSCoinNotaryState = AcidState Storage

$(deriveSafeCopy 0 'base ''Storage)

openState :: FilePath -> [PublicKey] -> IO RSCoinNotaryState
openState fp trustedKeys =
    openLocalStateFrom fp S.emptyNotaryStorage { _masterKeys = trustedKeys }

openMemState :: [PublicKey] -> IO RSCoinNotaryState
openMemState trustedKeys =
    openMemoryState S.emptyNotaryStorage { _masterKeys = trustedKeys }

closeState :: RSCoinNotaryState -> IO ()
closeState = closeAcidState

$(makeAcidic ''Storage
             [ 'S.acquireSignatures
             , 'S.addSignedTransaction
             , 'S.allocateMSAddress
             , 'S.announceNewPeriods
             , 'S.getPeriodId
             , 'S.getSignatures
             , 'S.pollTransactions
             , 'S.queryAllMSAdresses
             , 'S.queryCompleteMSAdresses
             , 'S.queryMyMSRequests
             , 'S.removeCompleteMSAddresses
             ])
