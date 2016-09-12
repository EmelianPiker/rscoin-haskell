{-# LANGUAGE ScopedTypeVariables #-}

-- | Server implementation for Notary.

module RSCoin.Notary.Server
        ( serveNotary
        , handlePublishTx
        , handleAnnounceNewPeriods
        , handleGetPeriodId
        , handleGetPeriodIdUnsigned
        , handleGetSignatures
        , handleQueryCompleteMS
        , handleRemoveCompleteMS
        , handleAllocateMultisig
        ) where

import           Control.Applicative     (liftA2)
import           Control.Lens            ((^.))
import           Control.Monad           (unless)
import           Control.Monad.Catch     (MonadCatch, catch, throwM)
import           Control.Monad.Trans     (MonadIO)
import           Data.Binary             (Binary)
import           Data.Text               (Text)

import           Formatting              (build, int, sformat, shown, (%))

import           Serokell.Util.Text      (pairBuilder, show')

import           Control.TimeWarp.Rpc    (serverTypeRestriction0,
                                          serverTypeRestriction1,
                                          serverTypeRestriction2,
                                          serverTypeRestriction3,
                                          serverTypeRestriction5)
import qualified RSCoin.Core             as C
import qualified RSCoin.Core.Protocol    as P

import           RSCoin.Notary.AcidState (AddSignedTransaction (..),
                                          AllocateMSAddress (..),
                                          AnnounceNewPeriods (..),
                                          GetPeriodId (..), GetSignatures (..),
                                          NotaryState, PollPendingTxs (..),
                                          QueryAllMSAdresses (..),
                                          QueryCompleteMSAdresses (..),
                                          QueryMyMSRequests (..),
                                          RemoveCompleteMSAddresses (..), query,
                                          tidyState, update)
import           RSCoin.Notary.Error     (NotaryError (..))

type ServerTE m a = m (Either Text a)

type ServerTESigned m a = ServerTE m (C.WithSignature a)

toServer
    :: (C.WithNamedLogger m, MonadIO m, MonadCatch m)
    => m a -> ServerTE m a
toServer action = (Right <$> action) `catch` handler
  where
    handler (e :: NotaryError) = do
        C.logError $ sformat build e
        return $ Left $ show' e

signHandler
    :: (Binary a, Functor m)
    => C.SecretKey -> ServerTE m a -> ServerTESigned m a
signHandler sk = fmap (fmap (C.mkWithSignature sk))

toServerSigned
    :: (C.WithNamedLogger m, MonadIO m, MonadCatch m, Binary a)
    => C.SecretKey -> m a -> ServerTESigned m a
toServerSigned sk = signHandler sk . toServer

-- | Run Notary server which will process incoming sing requests.
serveNotary
    :: C.WorkMode m
    => C.SecretKey -> NotaryState -> m ()
serveNotary sk notaryState = do
    idr1 <- serverTypeRestriction3
    idr2 <- serverTypeRestriction2
    idr3 <- serverTypeRestriction3
    idr4 <- serverTypeRestriction0
    idr5 <- serverTypeRestriction0
    idr6 <- serverTypeRestriction2
    idr7 <- serverTypeRestriction5
    idr8 <- serverTypeRestriction1
    idr9 <- serverTypeRestriction1

    (bankPublicKey, notaryPort) <- liftA2 (,) (^. C.bankPublicKey) (^. C.notaryPort)
                                   <$> C.getNodeContext
    P.serve
        notaryPort
        [ P.method (P.RSCNotary P.PublishTransaction)         $ idr1
            $ handlePublishTx sk notaryState
        , P.method (P.RSCNotary P.GetSignatures)              $ idr2
            $ handleGetSignatures sk notaryState
        , P.method (P.RSCNotary P.AnnounceNewPeriodsToNotary) $ idr3
            $ handleAnnounceNewPeriods notaryState bankPublicKey
        , P.method (P.RSCNotary P.GetNotaryPeriod)            $ idr4
            $ handleGetPeriodId sk notaryState
        , P.method (P.RSCNotary P.QueryCompleteMS)            $ idr5
            $ handleQueryCompleteMS sk notaryState
        , P.method (P.RSCNotary P.RemoveCompleteMS)           $ idr6
            $ handleRemoveCompleteMS notaryState bankPublicKey
        , P.method (P.RSCNotary P.AllocateMultisig)           $ idr7
            $ handleAllocateMultisig notaryState
        , P.method (P.RSCNotary P.QueryMyAllocMS)             $ idr8
            $ handleQueryMyAllocationMS sk notaryState
        , P.method (P.RSCNotary P.PollPendingTransactions)    $ idr9
            $ handlePollPendingTxs sk notaryState
        ]

handlePublishTx
    :: (C.WithNamedLogger m, MonadIO m, MonadCatch m)
    => C.SecretKey
    -> NotaryState
    -> C.Transaction
    -> C.Address
    -> (C.Address, C.Signature C.Transaction)
    -> ServerTESigned m [(C.Address, C.Signature C.Transaction)]
handlePublishTx sk st tx addr sg =
    toServerSigned sk $
    do update st $ AddSignedTransaction tx addr sg
       res <- query st $ GetSignatures tx
       C.logDebug $
           sformat
               ("Getting signatures for tx " % build % ", addr " % build % ": " %
                build)
               tx
               addr
               res
       return res

handleAnnounceNewPeriods
    :: (C.WithNamedLogger m, MonadIO m, MonadCatch m)
    => NotaryState
    -> C.PublicKey
    -> C.PeriodId
    -> [C.HBlock]
    -> C.Signature [C.HBlock]
    -> ServerTE m ()
handleAnnounceNewPeriods st bankPk pId hblocks hblocksSig = toServer $ do
--    DEBUG
--    outdatedAllocs <- query st OutdatedAllocs
--    C.logDebug $ sformat ("All discard info: " % shown) outdatedAllocs
    unless (C.verify bankPk hblocksSig hblocks) $
        throwM NEInvalidSignature

    update st $ AnnounceNewPeriods pId hblocks
    tidyState st
    C.logDebug $ sformat ("New period announcement, hblocks " % build % " from periodId " % int)
        hblocks
        pId

handleGetPeriodId
    :: (C.WithNamedLogger m, MonadIO m, MonadCatch m)
    => C.SecretKey -> NotaryState -> ServerTESigned m C.PeriodId
handleGetPeriodId sk st = signHandler sk $ handleGetPeriodIdUnsigned st

handleGetPeriodIdUnsigned
    :: (C.WithNamedLogger m, MonadIO m, MonadCatch m)
    => NotaryState -> ServerTE m C.PeriodId
handleGetPeriodIdUnsigned st =
    toServer $
    do res <- query st GetPeriodId
       res <$ C.logDebug (sformat ("Getting periodId: " % int) res)

-- @TODO: remove 'C.Address' argument
handleGetSignatures
    :: (C.WithNamedLogger m, MonadIO m, MonadCatch m)
    => C.SecretKey
    -> NotaryState
    -> C.Transaction
    -> C.Address
    -> ServerTESigned m [(C.Address, C.Signature C.Transaction)]
handleGetSignatures sk st tx addr =
    toServerSigned sk $
    do res <- query st $ GetSignatures tx
       C.logDebug $
           sformat
               ("Getting signatures for tx " % build % ", addr " % build % ": " %
                build)
               tx
               addr
               res
       return res

handleQueryCompleteMS
    :: (C.WithNamedLogger m, MonadIO m, MonadCatch m)
    => C.SecretKey
    -> NotaryState
    -> ServerTESigned m [(C.Address, C.TxStrategy)]
handleQueryCompleteMS sk st =
    toServerSigned sk $
    do res <- query st QueryCompleteMSAdresses
       C.logDebug $ sformat ("Getting complete MS: " % shown) res
       return res

handleRemoveCompleteMS
    :: (C.WithNamedLogger m, MonadIO m, MonadCatch m)
    => NotaryState
    -> C.PublicKey
    -> [C.Address]
    -> C.Signature [C.MSAddress]
    -> ServerTE m ()
handleRemoveCompleteMS st bankPublicKey addresses signedAddrs = toServer $ do
    C.logDebug $ sformat ("Removing complete MS of " % shown) addresses
    update st $ RemoveCompleteMSAddresses bankPublicKey addresses signedAddrs

handleAllocateMultisig
    :: (C.WithNamedLogger m, MonadIO m, MonadCatch m)
    => NotaryState
    -> C.Address
    -> C.PartyAddress
    -> C.AllocationStrategy
    -> C.Signature (C.MSAddress, C.AllocationStrategy)
    -> Maybe (C.PublicKey, C.Signature C.PublicKey)
    -> ServerTE m ()
handleAllocateMultisig st msAddr partyAddr allocStrat signature mMasterCheck = toServer $ do
    C.logDebug "Begining allocation MS address..."
    C.logDebug $
        sformat ("SigPair: " % build % ", Chain: " % build) signature (pairBuilder <$> mMasterCheck)
    update st $ AllocateMSAddress msAddr partyAddr allocStrat signature mMasterCheck

    -- @TODO: get query only in Debug mode
    currentMSAddresses <- query st QueryAllMSAdresses
    C.logDebug $ sformat ("All addresses: " % shown) currentMSAddresses

handleQueryMyAllocationMS
    :: (C.WithNamedLogger m, MonadIO m, MonadCatch m)
    => C.SecretKey
    -> NotaryState
    -> C.AllocationAddress
    -> ServerTESigned m [(C.MSAddress, C.AllocationInfo)]
handleQueryMyAllocationMS sk st allocAddr =
    toServerSigned sk $
    do C.logDebug "Querying my MS allocations..."
       query st $ QueryMyMSRequests allocAddr

handlePollPendingTxs
    :: (C.WithNamedLogger m, MonadIO m, MonadCatch m)
    => C.SecretKey
    -> NotaryState
    -> [C.Address]
    -> ServerTESigned m [C.Transaction]
handlePollPendingTxs sk st parties =
    toServerSigned sk $
    do C.logDebug "Polling pending txs..."
       query st $ PollPendingTxs parties
