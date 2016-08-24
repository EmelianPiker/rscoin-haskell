-- | Explorer Server.

module RSCoin.Explorer.Server
       ( serve
       ) where

import           Control.Exception         (throwIO)
import           Control.Lens              ((^.))
import           Control.Monad             (unless)
import           Control.Monad.Trans       (MonadIO (liftIO))
import           Formatting                (build, int, sformat, (%))

import           Serokell.Util.Text        (listBuilderJSONIndent)

import qualified RSCoin.Core               as C
import           RSCoin.Timed              (MonadRpc (getNodeContext), ServerT,
                                            WorkMode, serverTypeRestriction1,
                                            serverTypeRestriction3)

import           RSCoin.Explorer.AcidState (AddHBlock (..),
                                            GetLastPeriodId (..), GetTx (..),
                                            State, query, tidyState, update)
import           RSCoin.Explorer.Channel   (Channel, ChannelItem (..),
                                            writeChannel)
import           RSCoin.Explorer.Error     (ExplorerError (EEInvalidBankSignature))

serve
    :: WorkMode m
    => Int -> Channel -> State -> C.SecretKey -> m ()
serve port ch st _ = do
    idr1 <- serverTypeRestriction3
    idr2 <- serverTypeRestriction1
    bankPublicKey <- (^. C.bankPublicKey) <$> getNodeContext
    C.serve
        port
        [ C.method (C.RSCExplorer C.EMNewBlock) $
          idr1 $ handleNewHBlock ch st bankPublicKey
        , C.method (C.RSCExplorer C.EMGetTransaction) $
          idr2 $ handleGetTransaction st]

handleGetTransaction
    :: WorkMode m
    => State -> C.TransactionId -> ServerT m (Maybe C.Transaction)
handleGetTransaction st tId = do
    tx <- query st (GetTx tId)
    let msg =
            sformat
                ("Getting transaction with id " % build % ": " % build)
                tId
                tx
    tx <$ C.logDebug msg

handleNewHBlock
    :: WorkMode m
    => Channel
    -> State
    -> C.PublicKey
    -> C.PeriodId
    -> (C.HBlock, C.EmissionId)
    -> C.Signature (C.PeriodId, C.HBlock)
    -> ServerT m C.PeriodId
handleNewHBlock ch st bankPublicKey newBlockId (newBlock,emission) sig = do
    C.logInfo $ sformat ("Received new block #" % int) newBlockId
    unless (C.verify bankPublicKey sig (newBlockId, newBlock)) $
        liftIO $ throwIO EEInvalidBankSignature
    expectedPid <- maybe 0 succ <$> query st GetLastPeriodId
    let ret p = do
            C.logDebug $ sformat ("Now expected block is #" % int) p
            return p
        upd = do
            C.logDebug $ sformat ("HBlock hash: " % build) (C.hash newBlock)
            C.logDebug $ sformat ("HBlock emission: " % build) emission
            C.logDebug $
                sformat ("Transaction hashes: " % build) $
                listBuilderJSONIndent 2 $
                map (C.hash :: C.Transaction -> C.Hash C.Transaction) $
                C.hbTransactions newBlock
            C.logDebug $
                sformat ("Transactions: " % build) $
                listBuilderJSONIndent 2 $ C.hbTransactions newBlock
            update st (AddHBlock newBlockId newBlock emission)
            writeChannel
                ch
                ChannelItem
                { ciTransactions = C.hbTransactions newBlock
                }
            tidyState st
            ret (newBlockId + 1)
    if expectedPid == newBlockId
        then upd
        else ret expectedPid
