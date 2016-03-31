{-# LANGUAGE ScopedTypeVariables #-}

-- | Server implementation for mintette

module RSCoin.Mintette.Server
       ( serve
       ) where

import           Control.Exception         (bracket, catch, throwIO, try)
import           Control.Monad.IO.Class    (liftIO)
import           Data.Acid.Advanced        (query', update')
import           Data.Monoid               ((<>))
import           Data.Text                 (Text)

import           Serokell.Util.Text        (format', formatSingle',
                                            listBuilderJSONIndent, show')

import qualified RSCoin.Core               as C
import           RSCoin.Mintette.AcidState (CheckNotDoubleSpent (..),
                                            CommitTx (..), FinishPeriod (..),
                                            PreviousMintetteId (..),
                                            StartPeriod (..), State, closeState,
                                            openState)
import           RSCoin.Mintette.Error     (MintetteError)
import           RSCoin.Mintette.Worker    (runWorker)

serve :: Int -> FilePath -> C.SecretKey -> IO ()
serve port dbPath sk =
    bracket (openState dbPath) closeState $
    \st ->
         do runWorker sk st
            C.serve port
                [ C.method (C.RSCMintette C.PeriodFinished) $ handlePeriodFinished sk st
                , C.method (C.RSCMintette C.AnnounceNewPeriod) $ handleNewPeriod st
                , C.method (C.RSCMintette C.CheckTx) $ handleCheckTx sk st
                , C.method (C.RSCMintette C.CommitTx) $ handleCommitTx sk st
                ]

toServer :: IO a -> C.Server a
toServer action = liftIO $ action `catch` handler
  where
    handler (e :: MintetteError) = do
        C.logError $ show' e
        throwIO e

handlePeriodFinished
    :: C.SecretKey -> State -> C.PeriodId -> C.Server C.PeriodResult
handlePeriodFinished sk st pId =
    toServer $
    do C.logInfo $ formatSingle' "Period {} has just finished!" pId
       res@(_,blks,lgs) <- update' st $ FinishPeriod sk pId
       C.logInfo $
           format'
               "Here is PeriodResult:\n Blocks: {}\n Logs: {}\n"
               (listBuilderJSONIndent 2 blks, lgs)
       return res

handleNewPeriod :: State
                -> C.NewPeriodData
                -> C.Server ()
handleNewPeriod st npd =
    toServer $
    do prevMid <- query' st PreviousMintetteId
       C.logInfo $
           format'
               ("New period has just started, I am mintette #{} (prevId).\n" <>
                "Here is new period data:\n {}")
               (prevMid, npd)
       update' st $ StartPeriod npd

handleCheckTx
    :: C.SecretKey
    -> State
    -> C.Transaction
    -> C.AddrId
    -> C.Signature
    -> C.Server (Either Text C.CheckConfirmation)
handleCheckTx sk st tx addrId sg =
    toServer $
    do C.logDebug $
           format' "Checking addrid ({}) from transaction: {}" (addrId, tx)
       res <- try $ update' st $ CheckNotDoubleSpent sk tx addrId sg
       either onError onSuccess res
  where
    onError (e :: MintetteError) = do
        C.logWarning $ formatSingle' "CheckTx failed: {}" e
        return $ Left $ show' e
    onSuccess res = do
        C.logInfo $
            format' "Confirmed addrid ({}) from transaction: {}" (addrId, tx)
        C.logInfo $ formatSingle' "Confirmation: {}" res
        return $ Right $ res

handleCommitTx
    :: C.SecretKey
    -> State
    -> C.Transaction
    -> C.PeriodId
    -> C.CheckConfirmations
    -> C.Server (Either Text C.CommitConfirmation)
handleCommitTx sk st tx pId cc =
    toServer $
    do C.logDebug $
           format'
               "There is an attempt to commit transaction ({}), provided periodId is {}."
               (tx, pId)
       C.logDebug $ formatSingle' "Here are confirmations: {}" cc
       res <- try $ update' st $ CommitTx sk tx pId cc
       either onError onSuccess res
  where
    onError (e :: MintetteError) = do
        C.logWarning $ formatSingle' "CommitTx failed: {}" e
        return $ Left $ show' e
    onSuccess res = do
        C.logInfo $ formatSingle' "Successfully committed transaction {}" tx
        return $ Right res
