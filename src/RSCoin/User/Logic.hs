{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}

-- | This module reperents all logic that abstract client should have
-- in its arsenal -- mostly the algorithmic part of user in paper,
-- requests to bank/mintettes and related things.

module RSCoin.User.Logic
       ( CC.getBlockByHeight
       , CC.getBlockchainHeight
       , SignatureBundle
       , joinBundles
       , getExtraSignatures
       , validateTransaction
       ) where

import           Control.Monad                 (guard, unless, when)
import           Control.Monad.Catch           (throwM)
import           Control.Monad.Trans           (liftIO)
import           Data.Either                   (partitionEithers)
import           Data.Either.Combinators       (fromLeft', isLeft, rightToMaybe)
import           Data.List                     (genericLength, nub)
import qualified Data.Map                      as M
import           Data.Maybe                    (catMaybes, fromJust)
import           Data.Monoid                   ((<>))
import           Data.Tuple.Select             (sel1, sel2, sel3)
import           System.Timeout                (timeout)

import           RSCoin.Core.CheckConfirmation (verifyCheckConfirmation)
import qualified RSCoin.Core.Communication     as CC
import           RSCoin.Core.Crypto            (Signature, verify)
import           RSCoin.Core.Logging           (logWarning, userLoggerName)
import           RSCoin.Core.Primitives        (AddrId, Address,
                                                Transaction (..))
import           RSCoin.Core.Strategy          (isStrategyCompleted)
import           RSCoin.Core.Types             (CheckConfirmations,
                                                CommitConfirmation, Mintette,
                                                MintetteId, PeriodId,
                                                Strategy (..))
import           RSCoin.Mintette.Error         (MintetteError)
import           RSCoin.Timed                  (WorkMode)
import           RSCoin.User.Cache             (UserCache, getOwnersByAddrid,
                                                getOwnersByTx,
                                                invalidateUserCache)
import           RSCoin.User.Error             (UserLogicError (..))

import           Serokell.Util.Text            (format', formatSingle',
                                                listBuilderJSON, pairBuilder)

-- | SignatureBundle is a datatype that represents signatures needed
-- to prove that address owners are OK with transaction spending money
-- from that address
type SignatureBundle = M.Map AddrId (Address, Strategy, [(Address,Signature)])

joinBundles
    :: (a, b, [(Address, Signature)])
    -> (a, b, [(Address, Signature)])
    -> (a, b, [(Address, Signature)])
joinBundles (a,s,signs1) (_,_,signs2) = (a,s,nub $ signs1 ++ signs2)

-- | Gets signatures that can't be retrieved locally (for strategies
-- other than local).
getExtraSignatures
    :: WorkMode m
    => Transaction                                 -- ^ Transaction to confirm addrid from
    -> M.Map Address (Strategy,[AddrId],Signature) -- ^ Addresses with special strategies
                                                   -- to spend money from
    -> Int                                         -- ^ Timeout in seconds
    -> m (Maybe SignatureBundle)                   -- ^ Nothing means transaction was
                                                   -- already sent by someone, (Just sgs)
                                                   -- means user should send it.
getExtraSignatures tx requests time = do
    unless checkInput $ error "Wrong input of getExtraSignatures"
    (waiting,ready) <- partitionEithers <$> mapM perform (M.keys requests)
    if null waiting
    then return Nothing
    else do
        timeoutRes <- liftIO $ timeout time $ pingUntilDead waiting []
        maybe (error "Timeout failed")
              (return . Just . toBundle . (++ ready))
              timeoutRes
  where
    lookupMap addr = fromJust $ M.lookup addr requests
    getStrategy = sel1 . lookupMap
    getAddrIds = sel2 . lookupMap
    getOwnSignature = sel3 . lookupMap
    checkInput = all (`elem` txInputs tx) $ concatMap sel2 $ M.elems requests
    toBundle =
        M.fromListWith joinBundles .
        concatMap (\(addr,signs) ->
            let str = getStrategy addr
                addrids = getAddrIds addr
            in map (,(addr,str,signs)) addrids)
    pingUntilDead [] ready = return ready
    pingUntilDead notReady@(addr:otherAddrs) ready = do
        sigs <- CC.getTxSignatures tx addr
        if isStrategyCompleted (getStrategy addr) addr sigs tx
        then pingUntilDead otherAddrs $ (addr,sigs):ready
        else pingUntilDead notReady ready
    -- Returns (Right signs) if for address:
    -- 1. First poll showed signatures are ready
    -- 2. After our signature commit signatures became ready
    -- Returns (Left addr) if signer should be polled for transaction tx
    -- and addr `addr` and sigs are not ready
    perform :: WorkMode m
            => Address
            -> m (Either Address (Address, [(Address,Signature)]))
    perform addr = do
        let returnRight s = return $ Right (addr,s)
            strategy = getStrategy addr
            ownSg = getOwnSignature addr
        curSigs <- CC.getTxSignatures tx addr
        if isStrategyCompleted strategy addr curSigs tx
        then returnRight curSigs
        else do
            afterPublishSigs <- CC.publishTxToSigner tx (addr,ownSg)
            if isStrategyCompleted strategy addr afterPublishSigs tx
            then returnRight afterPublishSigs
            else return $ Left addr

-- | Implements V.1 from the paper. For all addrids that are inputs of
-- transaction 'signatures' should contain signature of transaction
-- given. If transaction is confirmed, just returns. If it's not
-- confirmed, the MajorityFailedToCommit is thrown.
validateTransaction
    :: WorkMode m
    => Maybe UserCache -- ^ User cache
    -> Transaction     -- ^ Transaction to send
    -> SignatureBundle -- ^ Signatures for local addresses with default strategy
    -> PeriodId        -- ^ Period in which the transaction should be sent
    -> m ()
validateTransaction cache tx@Transaction{..} signatureBundle height = do
    unless (all checkStrategy $ M.elems signatureBundle) $ throwM StrategyFailed
    (bundle :: CheckConfirmations) <- mconcat <$> mapM processInput txInputs
    commitBundle bundle
  where
    checkStrategy :: (Address, Strategy, [(Address, Signature)]) -> Bool
    checkStrategy (addr,str,sgns) = isStrategyCompleted str addr sgns tx
    processInput
        :: WorkMode m
        => AddrId -> m CheckConfirmations
    processInput addrid = do
        owns <- getOwnersByAddrid cache height addrid
        when (null owns) $
            throwM $
            MajorityRejected $
            formatSingle' "Addrid {} doesn't have owners" addrid
        -- TODO maybe optimize it: we shouldn't query all mintettes, only the majority
        subBundle <- mconcat . catMaybes <$> mapM (processMintette addrid) owns
        when (length subBundle <= length owns `div` 2) $
            do invalidateCache
               throwM $
                   MajorityRejected $
                   format'
                       ("Couldn't get CheckNotDoubleSpent " <>
                        "from majority of mintettes: only {}/{} confirmed {} is not double-spent.")
                       (length subBundle, length owns, addrid)
        return subBundle
    processMintette
        :: WorkMode m
        => AddrId -> (Mintette, MintetteId) -> m (Maybe CheckConfirmations)
    processMintette addrid (mintette,mid) = do
        signedPairMb <-
            rightToMaybe <$>
            (CC.checkNotDoubleSpent mintette tx addrid $
             sel3 $ fromJust $ M.lookup addrid signatureBundle)
        return $
            signedPairMb >>=
            \proof ->
                 M.singleton (mid, addrid) proof <$
                 guard (verifyCheckConfirmation proof tx addrid)
    commitBundle
        :: WorkMode m
        => CheckConfirmations -> m ()
    commitBundle bundle = do
        owns <- getOwnersByTx cache height tx
        commitActions <-
            mapM
                (\(mintette,_) ->
                      CC.commitTx mintette tx height bundle)
                owns
        let succeededCommits :: [CommitConfirmation]
            succeededCommits =
                filter
                    (\(pk,sign,lch) ->
                          verify pk sign (tx, lch)) $
                catMaybes $ map rightToMaybe $ commitActions
            failures = filter isLeft commitActions
        unless (null failures) $
            logWarning userLoggerName $
            commitTxWarningMessage owns commitActions
        when (length succeededCommits <= length owns `div` 2) $
            do throwM $
                   MajorityFailedToCommit
                       (genericLength succeededCommits)
                       (genericLength owns)
    commitTxWarningMessage owns =
        formatSingle'
            "some mintettes returned error in response to `commitTx`: {}" .
        listBuilderJSON . map pairBuilder . mintettesAndErrors owns
    mintettesAndErrors
        :: [(Mintette, MintetteId)]
        -> [Either MintetteError CommitConfirmation]
        -> [(Mintette, MintetteError)]
    mintettesAndErrors owns =
        map sndFromLeft . filter (isLeft . snd) . zip (map fst owns)
    sndFromLeft :: (a, Either MintetteError b) -> (a, MintetteError)
    sndFromLeft (a,b) = (a, fromLeft' b)
    invalidateCache
        :: WorkMode m
        => m ()
    invalidateCache = liftIO $ maybe (return ()) invalidateUserCache cache
