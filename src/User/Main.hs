{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}

import           Control.Concurrent             (forkIO)
import           Control.Concurrent.STM.TBQueue (newTBQueueIO)
import           Control.Monad                  (void)
import           Control.Monad.Catch            (MonadCatch, bracket, catch,
                                                 throwM)
import           Control.Monad.Trans            (MonadIO, liftIO)
import qualified Data.Acid                      as ACID
import qualified Data.Text                      as T

import qualified RSCoin.Core                    as C
import           RSCoin.Timed                   (WorkMode, runRealMode)
import qualified RSCoin.User.AcidState          as A
import qualified RSCoin.User.Actions            as UA
import           RSCoin.User.Error              (eWrap)
import qualified RSCoin.User.Wallet             as W

import           GUI.RSCoin.Contacts            (ContactsList (..))
import           GUI.RSCoin.GUI                 (startGUI)
import qualified UserOptions                    as O

actionsQueueCapacity :: Int
actionsQueueCapacity = 10

-- | Processes command line user command
processCommand
    :: WorkMode m => A.RSCoinUserState -> O.UserCommand -> FilePath -> m ()
processCommand st O.ListAddresses _ = UA.processAction st UA.ListAddresses
processCommand st (O.FormTransaction i o) _ = UA.processAction st $ UA.FormTransaction i o
processCommand st O.UpdateBlockchain _ = UA.processAction st UA.UpdateBlockchain
processCommand _ (O.Dump command) _ = eWrap $ dumpCommand command
processCommand st O.StartGUI contactsPath = -- TODO Refactor it outside
    bracket
        (liftIO $ ACID.openLocalStateFrom contactsPath $ ContactsList [])
        (\cs ->
              liftIO $
              do ACID.createCheckpoint cs
                 ACID.closeAcidState cs)
        (\cs -> liftIO startGUI)

dumpCommand :: WorkMode m => O.DumpCommand -> m ()
dumpCommand O.DumpMintettes                = void   C.getMintettes
dumpCommand O.DumpPeriod                   = void   C.getBlockchainHeight
dumpCommand (O.DumpHBlocks from to)        = void $ C.getBlocks from to
dumpCommand (O.DumpHBlock pId)             = void $ C.getBlockByHeight pId
dumpCommand (O.DumpLogs mId from to)       = void $ C.getLogs mId from to
dumpCommand (O.DumpMintetteUtxo mId)       = void $ C.getMintetteUtxo mId
dumpCommand (O.DumpMintetteBlocks mId pId) = void $ C.getMintetteBlocks mId pId
dumpCommand (O.DumpMintetteLogs mId pId)   = void $ C.getMintetteLogs mId pId

main :: IO ()
main = do
    opts@O.UserOptions{..} <- O.getUserOptions
    C.initLogging logSeverity
    runRealMode $
        bracket
            (liftIO $ A.openState walletPath)
            (\st -> liftIO $ do
                ACID.createCheckpoint st
                A.closeState st) $
            \st ->
                 do C.logDebug C.userLoggerName $
                        mconcat ["Called with options: ", (T.pack . show) opts]
                    handleUnitialized
                        (processCommand st userCommand contactsPath)
                        (A.initState st addressesNum $
                            bankKeyPath isBankMode bankModePath)
  where
    handleUnitialized :: (MonadIO m, MonadCatch m) => m () -> m () -> m ()
    handleUnitialized action initialization =
        action `catch` handler initialization action
      where
        handler i a W.NotInitialized =
            C.logInfo C.userLoggerName "Initalizing storage..." >> i >> a
        handler _ _ e = throwM e
    bankKeyPath True  p = Just p
    bankKeyPath False _ = Nothing
