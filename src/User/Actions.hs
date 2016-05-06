{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}

-- | Module that provides some functions that transform
-- UserOptions.UserCommand s to IO actions.

module Actions (proceedCommand) where

import           Control.Concurrent             (forkIO)
import           Control.Concurrent.STM.TBQueue (newTBQueueIO)
import           Control.Lens                   ((^.))
import           Control.Monad                  (forM_, unless, void, when)
import           Control.Monad.Catch            (throwM)
import           Control.Monad.Trans            (liftIO)
import           Data.Acid                      (query)
import           Data.Maybe                     (fromJust, isJust)
import           Data.Monoid                    ((<>))
import qualified Data.Text.IO                   as TIO

import           Serokell.Util.Text             (format', formatSingle')

import           ActionsExecutor                (runActionsExecutor)
import           GUI                            (runGUI)
import           RSCoin.Core                    as C
import           RSCoin.Test                    (WorkMode)
import           RSCoin.User.AcidState          (GetAllAddresses (..))
import qualified RSCoin.User.AcidState          as A
import           RSCoin.User.Error              (UserError (..), eWrap)
import qualified RSCoin.User.Operations         as P
import qualified RSCoin.User.Wallet             as W
import           Updater                        (runUpdater)
import qualified UserOptions                    as O

actionsQueueCapacity :: Int
actionsQueueCapacity = 10

-- | Given the state of program and command, makes correspondent
-- actions.
proceedCommand :: WorkMode m => A.RSCoinUserState -> O.UserCommand -> m ()
proceedCommand st O.StartGUI =
    eWrap $
    do
        queue <- liftIO $ newTBQueueIO actionsQueueCapacity
        ow <- liftIO $ runGUI queue
        liftIO $ void $ forkIO $ runUpdater queue
        runActionsExecutor st queue ow
proceedCommand st O.ListAddresses =
    liftIO $ eWrap $
    do (wallets :: [(C.PublicKey, C.Coin)]) <-
           mapM (\w -> (w ^. W.publicAddress, ) <$> P.getAmount st w) =<<
           query st GetAllAddresses
       TIO.putStrLn "Here's the list of your accounts:"
       TIO.putStrLn "# | Public ID                                    | Amount"
       mapM_ (TIO.putStrLn . format' "{}.  {} : {}") $
           uncurry (zip3 [(1 :: Integer) ..]) $ unzip wallets
proceedCommand st (O.FormTransaction inputs outputAddrStr) =
    eWrap $
    do let pubKey = C.Address <$> C.constructPublicKey outputAddrStr
       unless (isJust pubKey) $
           P.commitError $
           "Provided key can't be exported: " <> outputAddrStr
       P.formTransaction st inputs (fromJust pubKey) $
           C.Coin (sum $ map snd inputs)
proceedCommand st O.UpdateBlockchain =
    eWrap $
    do walletHeight <- liftIO $ query st A.GetLastBlockId
       liftIO $ TIO.putStrLn $
           formatSingle'
               "Current known blockchain's height (last HBLock's id) is {}."
               walletHeight
       lastBlockHeight <- pred <$> getBlockchainHeight
       when (walletHeight > lastBlockHeight) $
           throwM $
           StorageError $
           W.InternalError $
           format'
               ("Last block height in wallet ({}) is greater than last " <>
                "block's height in bank ({}). Critical error.")
               (walletHeight, lastBlockHeight)
       if lastBlockHeight == walletHeight
           then liftIO $ putStrLn "Blockchain is updated already."
           else do
               forM_
                  [walletHeight + 1 .. lastBlockHeight]
                  (\h -> do
                        liftIO $ TIO.putStr $
                            formatSingle' "Updating to height {} ..." h
                        P.updateToBlockHeight st h
                        liftIO $ TIO.putStrLn $
                            formatSingle' "updated to height {}" h)
               liftIO $ TIO.putStrLn "Successfully updated blockchain!"
proceedCommand _ (O.Dump command) = eWrap $ dumpCommand command

dumpCommand :: WorkMode m => O.DumpCommand -> m ()
dumpCommand (O.DumpHBlocks from to) =
    void $ C.getBlocks from to
dumpCommand (O.DumpHBlock pId) =
    void $ C.getBlockByHeight pId
dumpCommand O.DumpMintettes =
    void $ C.getMintettes
dumpCommand O.DumpPeriod =
    void $ C.getBlockchainHeight
dumpCommand (O.DumpLogs mId from to) =
    void $ C.getLogs mId from to
dumpCommand (O.DumpMintetteUtxo mId) =
    void $ C.getMintetteUtxo mId
dumpCommand (O.DumpMintetteBlocks mId pId) =
    void $ C.getMintetteBlocks mId pId
dumpCommand (O.DumpMintetteLogs mId pId) =
    void $ C.getMintetteLogs mId pId
