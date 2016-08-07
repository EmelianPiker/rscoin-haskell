{-# LANGUAGE ScopedTypeVariables #-}

-- | Server implementation for mintette

module Test.RSCoin.Full.Mintette.Server
       ( serve
       ) where

import           Control.Exception                (throwIO, try)
import           Control.Monad.Catch              (catch)
import           Control.Monad.IO.Class           (MonadIO, liftIO)
import           Data.Acid.Advanced               (query', update')
import           Data.Text                        (Text)
import           Formatting                       (build, sformat, (%))

import           Serokell.Util.Text               (show')

import qualified RSCoin.Core                      as C
import           RSCoin.Mintette.Acidic           (GetUtxoPset (..))
import           RSCoin.Mintette.AcidState        (State)
import           RSCoin.Mintette.Error            (MintetteError)
import qualified RSCoin.Mintette.Server           as OMS
import           RSCoin.Timed                     (ServerT, WorkMode,
                                                   serverTypeRestriction0,
                                                   serverTypeRestriction1,
                                                   serverTypeRestriction2,
                                                   serverTypeRestriction3)

import qualified Test.RSCoin.Full.Mintette.Acidic as MA
import           Test.RSCoin.Full.Mintette.Config (MintetteConfig)

logError, logWarning, logInfo, logDebug :: MonadIO m => Text -> m ()
logError = C.logError C.mintetteLoggerName
logWarning = C.logWarning C.mintetteLoggerName
logInfo = C.logInfo C.mintetteLoggerName
logDebug = C.logDebug C.mintetteLoggerName

-- | Serve as mintette according to mintette config provided
serve
    :: WorkMode m
    => MintetteConfig -> Int -> State -> C.SecretKey -> m ()
serve conf port st sk = do
    idr1 <- serverTypeRestriction1
    idr2 <- serverTypeRestriction1
    idr3 <- serverTypeRestriction3
    idr4 <- serverTypeRestriction2
    idr5 <- serverTypeRestriction0
    idr6 <- serverTypeRestriction1
    idr7 <- serverTypeRestriction1
    C.serve port
        [ C.method (C.RSCMintette C.PeriodFinished) $
            idr1 $ OMS.handlePeriodFinished sk st
        , C.method (C.RSCMintette C.AnnounceNewPeriod) $
            idr2 $ OMS.handleNewPeriod st
        , C.method (C.RSCMintette C.CheckTx) $
            idr3 $ handleCheckTx sk st conf
        , C.method (C.RSCMintette C.CommitTx) $
            idr4 $ handleCommitTx sk st conf
        , C.method (C.RSCDump C.GetMintetteUtxo) $
            idr5 $ OMS.handleGetUtxo st
        , C.method (C.RSCDump C.GetMintetteBlocks) $
            idr6 $ OMS.handleGetBlocks st
        , C.method (C.RSCDump C.GetMintetteLogs) $
            idr7 $ OMS.handleGetLogs st
        ]

toServer :: WorkMode m => IO a -> ServerT m a
toServer action = liftIO $ action `catch` handler
  where
    handler (e :: MintetteError) = do
        logError $ show' e
        throwIO e

handleCheckTx
    :: WorkMode m
    => C.SecretKey
    -> State
    -> MintetteConfig
    -> C.Transaction
    -> C.AddrId
    -> [(C.Address, C.Signature)]
    -> ServerT m (Maybe C.CheckConfirmation)
handleCheckTx sk st conf tx addrId sg =
    toServer $
    do logDebug $
           sformat ("Checking addrid (" % build % ") from transaction: " % build) addrId tx
       (curUtxo,curPset) <- query' st GetUtxoPset
       logDebug $
           sformat
               ("My current utxo is: " % build % "\nCurrent pset is: " % build)
               curUtxo curPset
       res <- try $ update' st $ MA.CheckNotDoubleSpent conf sk tx addrId sg
       either onError onSuccess res
  where
    onError (e :: MintetteError) = do
        logWarning $ sformat ("CheckTx failed: " % build) e
        return Nothing
    onSuccess res = do
        logInfo $
            sformat ("Confirmed addrid (" % build %
                     ") from transaction: " % build) addrId tx
        logInfo $ sformat ("Confirmation: " % build) res
        return $ Just res

handleCommitTx
    :: WorkMode m
    => C.SecretKey
    -> State
    -> MintetteConfig
    -> C.Transaction
    -> C.CheckConfirmations
    -> ServerT m (Maybe C.CommitAcknowledgment)
handleCommitTx sk st conf tx cc =
    toServer $
    do logDebug $
           sformat ("There is an attempt to commit transaction (" % build % ")") tx
       logDebug $ sformat ("Here are confirmations: " % build) cc
       res <- try $ update' st $ MA.CommitTx conf sk tx cc
       either onError onSuccess res
  where
    onError (e :: MintetteError) = do
        logWarning $ sformat ("CommitTx failed: " % build) e
        return Nothing
    onSuccess res = do
        logInfo $ sformat ("Successfully committed transaction " % build) tx
        return $ Just res
