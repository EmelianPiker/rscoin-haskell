{-# LANGUAGE ScopedTypeVariables #-}

-- | Server implementation for Bank

module RSCoin.Bank.Server
       ( serve
       ) where

import           Control.Concurrent    (MVar, newMVar, putMVar, takeMVar)
import           Control.Monad.Catch   (catch, throwM)
import           Control.Monad.Trans   (lift, liftIO)
import           Data.Acid.Advanced    (query', update')

import           Serokell.Util.Text    (format', formatSingle', mapBuilder,
                                        show')

import qualified Data.Map              as M
import           RSCoin.Bank.AcidState (AddAddress (..), GetAddresses (..),
                                        GetHBlock (..), GetHBlocks (..),
                                        GetLogs (..), GetMintettes (..),
                                        GetPeriodId (..), GetTransaction (..),
                                        State)
import           RSCoin.Bank.Error     (BankError)
import           RSCoin.Core           (ActionLog, Address, AddressStrategyMap,
                                        HBlock, MintetteId, Mintettes, PeriodId,
                                        Signature, Strategy, Transaction,
                                        TransactionId, bankLoggerName, bankPort,
                                        logDebug, logError, logInfo)
import qualified RSCoin.Core.Protocol  as C
import qualified RSCoin.Timed          as T

serve
    :: T.WorkMode m
    => State -> T.ThreadId -> (T.ThreadId -> m T.ThreadId) -> m ()
serve st workerThread restartWorkerAction = do
    threadIdMVar <- liftIO $ newMVar workerThread
    idr1 <- T.serverTypeRestriction0
    idr2 <- T.serverTypeRestriction0
    idr3 <- T.serverTypeRestriction1
    idr4 <- T.serverTypeRestriction1
    idr5 <- T.serverTypeRestriction0
    idr6 <- T.serverTypeRestriction2
    idr7 <- T.serverTypeRestriction3
    idr8 <- T.serverTypeRestriction0
    idr9 <- T.serverTypeRestriction3
    C.serve
        bankPort
        [ C.method (C.RSCBank C.GetMintettes) $ idr1 $ serveGetMintettes st
        , C.method (C.RSCBank C.GetBlockchainHeight) $ idr2 $ serveGetHeight st
        , C.method (C.RSCBank C.GetHBlock) $ idr3 $ serveGetHBlock st
        , C.method (C.RSCBank C.GetTransaction) $ idr4 $ serveGetTransaction st
        , C.method (C.RSCBank C.FinishPeriod) $
          idr5 $ serveFinishPeriod threadIdMVar restartWorkerAction
        , C.method (C.RSCDump C.GetHBlocks) $ idr6 $ serveGetHBlocks st
        , C.method (C.RSCDump C.GetHBlocks) $ idr7 $ serveGetLogs st
        , C.method (C.RSCBank C.GetAddresses) $ idr8 $ serveGetAddresses st
        , C.method (C.RSCBank C.AddStrategy) $ idr9 $ serveAddStrategy st
        ]

toServer :: T.WorkMode m => m a -> T.ServerT m a
toServer action = lift $ action `catch` handler
  where
    handler (e :: BankError) = do
        logError bankLoggerName $ show' e
        throwM e

-- toServer' :: T.WorkMode m => IO a -> T.ServerT m a
-- toServer' = toServer . liftIO

serveGetAddresses :: T.WorkMode m => State -> T.ServerT m AddressStrategyMap
serveGetAddresses st =
    toServer $
    do mts <- query' st GetAddresses
       logDebug bankLoggerName $ formatSingle' "Getting list of addresses: {}" $ mapBuilder $ M.toList mts
       return mts

serveGetMintettes :: T.WorkMode m => State -> T.ServerT m Mintettes
serveGetMintettes st =
    toServer $
    do mts <- query' st GetMintettes
       logDebug bankLoggerName $ formatSingle' "Getting list of mintettes: {}" mts
       return mts

serveGetHeight :: T.WorkMode m => State -> T.ServerT m PeriodId
serveGetHeight st =
    toServer $
    do pId <- query' st GetPeriodId
       logDebug bankLoggerName $ formatSingle' "Getting blockchain height: {}" pId
       return pId

serveGetHBlock :: T.WorkMode m
               => State -> PeriodId -> T.ServerT m (Maybe HBlock)
serveGetHBlock st pId =
    toServer $
    do mBlock <- query' st (GetHBlock pId)
       logDebug bankLoggerName $
           format' "Getting higher-level block with periodId {}: {}" (pId, mBlock)
       return mBlock

serveGetTransaction :: T.WorkMode m
                    => State -> TransactionId -> T.ServerT m (Maybe Transaction)
serveGetTransaction st tId =
    toServer $
    do t <- query' st (GetTransaction tId)
       logDebug bankLoggerName $
           format' "Getting transaction with id {}: {}" (tId, t)
       return t

serveFinishPeriod
    :: T.WorkMode m
    => MVar T.ThreadId -> (T.ThreadId -> m T.ThreadId) -> T.ServerT m ()
serveFinishPeriod threadIdMVar restartAction =
    toServer $
    do logInfo bankLoggerName $ "Forced finish of period was requested"
       -- TODO: consider using modifyMVar_ here
       liftIO (takeMVar threadIdMVar) >>= restartAction >>=
           liftIO . putMVar threadIdMVar

-- Dumping Bank state

serveGetHBlocks :: T.WorkMode m
                => State -> PeriodId -> PeriodId -> T.ServerT m [HBlock]
serveGetHBlocks st from to =
    toServer $
    do blocks <- query' st $ GetHBlocks from to
       logDebug bankLoggerName $
           format' "Getting higher-level blocks between {} and {}"
           (from, to)
       return blocks

serveGetLogs :: T.WorkMode m
             => State -> MintetteId -> Int -> Int -> T.ServerT m (Maybe ActionLog)
serveGetLogs st m from to =
    toServer $
    do mLogs <- query' st (GetLogs m from to)
       logDebug bankLoggerName $
           format' "Getting action logs of mintette {} with range of entries {} to {}: {}" (m, from, to, mLogs)
       return mLogs

serveAddStrategy
    :: T.WorkMode m
    => State -> Address -> Strategy -> [(Address, Signature)] -> T.ServerT m ()
serveAddStrategy st addr str _ =
    toServer $
    do logInfo bankLoggerName "Adding new strategy."
       update' st $ AddAddress addr str
