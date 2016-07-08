{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies    #-}
{-# OPTIONS_GHC -fno-warn-missing-signatures #-}

-- | Wrap Storage into AcidState

module RSCoin.Bank.AcidState
       ( State
       , openState
       , openMemState
       , closeState
       , GetMintettes (..)
       , GetPeriodId (..)
       , GetHBlock (..)
       , GetHBlocks (..)
       , GetTransaction (..)
       , GetLogs (..)
       , AddMintette (..)
       , StartNewPeriod (..)
       ) where

import           Control.Exception   (throw)
import           Control.Lens        (view)
import           Control.Monad.Catch (MonadThrow (throwM))
import           Data.Acid           (AcidState, Query, Update, closeAcidState,
                                      makeAcidic, openLocalStateFrom)
import           Data.Acid.Memory    (openMemoryState)

import           RSCoin.Core         (ActionLog, HBlock, Mintette, MintetteId,
                                      Mintettes, NewPeriodData, PeriodId,
                                      PeriodResult, PublicKey, SecretKey,
                                      Transaction, TransactionId)

import qualified RSCoin.Bank.Storage as BS

type State = AcidState BS.Storage

openState :: FilePath -> IO State
openState fp = openLocalStateFrom fp BS.mkStorage

openMemState :: IO State
openMemState = openMemoryState BS.mkStorage

closeState :: State -> IO ()
closeState = closeAcidState

instance MonadThrow (Update s) where
    throwM = throw

getMintettes :: Query BS.Storage Mintettes
getMintettes = view BS.getMintettes

getPeriodId :: Query BS.Storage PeriodId
getPeriodId = view BS.getPeriodId

getHBlock :: PeriodId -> Query BS.Storage (Maybe HBlock)
getHBlock = view . BS.getHBlock

getTransaction :: TransactionId -> Query BS.Storage (Maybe Transaction)
getTransaction = view . BS.getTransaction

-- Dumping Bank state

getHBlocks :: PeriodId -> PeriodId -> Query BS.Storage [HBlock]
getHBlocks from to = view $ BS.getHBlocks from to

getLogs :: MintetteId -> Int -> Int -> Query BS.Storage (Maybe ActionLog)
getLogs m from to = view $ BS.getLogs m from to

-- Dumping Bank state

addMintette :: Mintette -> PublicKey -> Update BS.Storage ()
addMintette = BS.addMintette

startNewPeriod
    :: SecretKey
    -> [Maybe PeriodResult]
    -> Update BS.Storage [NewPeriodData]
startNewPeriod = BS.startNewPeriod

$(makeAcidic ''BS.Storage
             [ 'getMintettes
             , 'getPeriodId
             , 'getHBlock
             , 'getHBlocks
             , 'getTransaction
             , 'getLogs
             , 'addMintette
             , 'startNewPeriod
             ])
