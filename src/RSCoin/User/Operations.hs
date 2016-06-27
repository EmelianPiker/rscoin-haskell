{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE PatternGuards       #-}
{-# LANGUAGE Rank2Types          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}

-- | Basic operations with wallet.

module RSCoin.User.Operations
       ( walletInitialized
       , commitError
       , getUserTotalAmount
       , getAmount
       , getAmountNoUpdate
       , getAmountByIndex
       , getAllPublicAddresses
       , getTransactionsHistory
       , updateToBlockHeight
       , updateBlockchain
       , formTransactionFromAll
       , FormTransactionInput
       , FormTransactionData (..)
       , formTransaction
       , formTransactionRetry
       ) where

import           Control.Exception      (SomeException, assert, fromException)
import           Control.Lens           ((^.))
import           Control.Monad          (filterM, forM_, unless, void, when)
import           Control.Monad.Catch    (MonadThrow, catch, throwM, try)
import           Control.Monad.IO.Class (MonadIO, liftIO)
import           Data.Acid.Advanced     (query', update')
import           Data.Function          (on)
import           Data.List              (genericIndex, genericLength, nubBy,
                                         sortOn)
import qualified Data.Map               as M
import           Data.Maybe             (fromJust, isNothing)
import           Data.Monoid            ((<>))
import qualified Data.Text              as T
import           Data.Text.Buildable    (Buildable)
import qualified Data.Text.IO           as TIO
import           Data.Tuple.Select      (sel1)
import           Formatting             (build, int, sformat, shown, (%))
import           Safe                   (atMay)

import           Serokell.Util          (format', formatSingle',
                                         listBuilderJSON, listBuilderJSONIndent,
                                         pairBuilder)

import qualified RSCoin.Core            as C
import           RSCoin.Mintette        (MintetteError (MEInactive))
import           RSCoin.Timed           (WorkMode, for, sec, wait)
import           RSCoin.User.AcidState  (GetAllAddresses (..))
import qualified RSCoin.User.AcidState  as A
import           RSCoin.User.Cache      (UserCache)
import           RSCoin.User.Error      (UserError (..), UserLogicError,
                                         isWalletSyncError)
import           RSCoin.User.Logic      (validateTransaction)
import qualified RSCoin.User.Wallet     as W

walletInitialized :: MonadIO m => A.RSCoinUserState -> m Bool
walletInitialized st = query' st A.IsInitialized

commitError :: (MonadIO m, MonadThrow m) => T.Text -> m a
commitError e = do
    C.logError C.userLoggerName e
    throwM . InputProcessingError $ e

-- | Updates wallet to given blockchain height assuming that it's in
-- previous height state already.
updateToBlockHeight :: WorkMode m => A.RSCoinUserState -> C.PeriodId -> m ()
updateToBlockHeight st newHeight = do
    C.HBlock{..} <- C.getBlockByHeight newHeight
    -- TODO validate this block with integrity check that we don't have
    update' st $ A.WithBlockchainUpdate newHeight hbTransactions

-- | Updates blockchain to the last height (that was requested in this
-- function call). Returns bool indicating that blockchain was or
-- wasn't updated. Does throw exception when update is not possible
-- due to some error. Thus 'False' return means that blockchain wasn't
-- updated and it's ok (already at max height)
updateBlockchain :: WorkMode m => A.RSCoinUserState -> Bool -> m Bool
updateBlockchain st verbose = do
    walletHeight <- query' st A.GetLastBlockId
    verboseSay $
        formatSingle'
            "Current known blockchain's height (last HBLock's id) is {}."
            walletHeight
    lastBlockHeight <- pred <$> C.getBlockchainHeight
    verboseSay $
        formatSingle'
            "Request showed that bank owns height {}."
            lastBlockHeight
    when (walletHeight > lastBlockHeight) $
        throwM $
        StorageError $
        W.InternalError $
        format'
            ("Last block height in wallet ({}) is greater than last " <>
             "block's height in bank ({}). Critical error.")
            (walletHeight, lastBlockHeight)
    when (lastBlockHeight /= walletHeight) $
        forM_
            [walletHeight + 1 .. lastBlockHeight]
            (\h ->
                  do verboseSay $ formatSingle' "Updating to height {} ..." h
                     updateToBlockHeight st h
                     verboseSay $ formatSingle' "updated to height {}" h)
    return $ lastBlockHeight /= walletHeight
  where
    verboseSay t = when verbose $ liftIO $ TIO.putStrLn t

-- | Gets amount of coins on user address
getAmount :: WorkMode m => A.RSCoinUserState -> W.UserAddress -> m C.CoinsMap
getAmount st userAddress = do
    -- try to update, but silently fail if net is down
    (_ :: Either SomeException Bool) <- try $ updateBlockchain st False
    getAmountNoUpdate st userAddress

-- | Gets current amount on all accounts user posesses. Boolean flag
-- stands for "if update blockchain inside"
getUserTotalAmount :: WorkMode m => Bool -> A.RSCoinUserState -> m C.CoinsMap
getUserTotalAmount upd st = do
    addrs <- query' st A.GetAllAddresses
    when upd $ void $ updateBlockchain st False
    C.mergeCoinsMaps <$> mapM (getAmountNoUpdate st) addrs

-- | Get amount without storage update
getAmountNoUpdate
    :: WorkMode m
    => A.RSCoinUserState -> W.UserAddress -> m C.CoinsMap
getAmountNoUpdate st userAddress =
    C.mergeCoinsMaps . map getCoins <$> query' st (A.GetTransactions userAddress)
  where
    getCoins = C.getAmountByAddress $ W.toAddress userAddress

-- | Gets amount of coins on user address, chosen by id (∈ 1..n, where
-- n is the number of accounts stored in wallet)
getAmountByIndex :: WorkMode m => A.RSCoinUserState -> Int -> m C.CoinsMap
getAmountByIndex st idx = do
    void $ updateBlockchain st False
    addr <- flip atMay idx <$> query' st A.GetAllAddresses
    maybe
        (throwM $
         InputProcessingError "invalid index was given to getAmountByIndex")
        (getAmount st)
        addr

-- | Returns list of public addresses available
getAllPublicAddresses :: WorkMode m => A.RSCoinUserState -> m [C.Address]
getAllPublicAddresses st = map C.Address <$> query' st A.GetPublicAddresses

-- | Returns transaction history that wallet holds
getTransactionsHistory :: WorkMode m => A.RSCoinUserState -> m [W.TxHistoryRecord]
getTransactionsHistory st = query' st A.GetTxsHistory

-- | Forms transaction given just amount of money to use. Tries to
-- spend coins from accounts that have the least amount of money.
-- Supports uncolored coins only (by design)
formTransactionFromAll
    :: WorkMode m
    => A.RSCoinUserState
    -> Maybe UserCache
    -> C.Address
    -> C.Coin
    -> m C.Transaction
formTransactionFromAll st maybeCache addressTo amount =
    assert (C.getColor amount == 0) $
    do addrs <- query' st A.GetAllAddresses
       (indicesWithCoins :: [(Word, C.Coin)]) <-
           filter ((>= 0) . snd) <$>
           mapM
               (\i ->
                     (fromIntegral i + 1, ) . M.findWithDefault 0 0 <$>
                     getAmountByIndex st i)
               [0 .. length addrs - 1]
       let totalAmount = C.sumCoin $ map snd indicesWithCoins
       when (amount > totalAmount) $
           throwM $
           InputProcessingError $
           format'
               "Tried to form transaction with amount ({}) greater than available ({})."
               (amount, totalAmount)
       let discoverAmount _ r@(left,_)
             | left <= 0 = r
           discoverAmount e@(i,c) (left,results) =
               let newLeft = left - c
               in if newLeft < 0
                      then (newLeft, (i, left) : results)
                      else (newLeft, e : results)
           (_,chosen) =
               foldr discoverAmount (amount, []) $ sortOn snd indicesWithCoins
           ftd =
               FormTransactionData
               { ftdInputs = map
                     (\(a,b) ->
                           (a, [b]))
                     chosen
               , ftdOutputAddress = addressTo
               , ftdOutputCoins = [amount]
               }
       C.logInfo C.userLoggerName $
           sformat ("Transaction chosen: " % shown) chosen
       formTransactionRetry 3 st maybeCache ftd

-- | A single input used to form transaction. It consists of two
-- things: index of wallet (zero-based) and non-empty list of coins to send.
type FormTransactionInput = (Word, [C.Coin])

data FormTransactionData = FormTransactionData
    {
      -- | List of inputs, see `FormTransactionInput` description.
      ftdInputs        :: [FormTransactionInput]
    ,
      -- | Output address where to send coins.
      ftdOutputAddress :: C.Address
    ,
      -- | List of coins to send. It may be empty, then will be
      -- calculated from inputs. Passing non-empty list is useful if
      -- one wants to color coins.
      ftdOutputCoins   :: [C.Coin]
    } deriving (Show)

-- | Forms transaction out of user input and sends it to the net.
formTransaction
    :: WorkMode m
    => A.RSCoinUserState
    -> Maybe UserCache
    -> FormTransactionData
    -> m C.Transaction
formTransaction = formTransactionRetry 1

-- | Forms transaction out of user input and sends it. If failure
-- occurs, waits for 1 sec, then retries up to given amout of tries.
formTransactionRetry
    :: forall m.
       WorkMode m
    => Word                 -- ^ Number of retries
    -> A.RSCoinUserState   -- ^ RSCoin user state (acid)
    -> Maybe UserCache     -- ^ Optional cache to decrease number of RPC
    -> FormTransactionData -- ^ Transaction description.
    -> m C.Transaction
formTransactionRetry tries st maybeCache ftd@FormTransactionData{..}
  | tries < 1 =
      error
          "User.Operations.formTransactionRetry shouldn't be called with tries < 1"
  | null ftdInputs = commitError "you should enter at least one source input"
  | otherwise = do
      (tx,signatures) <- constructAndSignTransaction st ftd
      tx <$ sendTransactionRetry tries st maybeCache tx signatures

type Signatures = M.Map C.AddrId C.Signature

constructAndSignTransaction
    :: forall m.
       WorkMode m
    => A.RSCoinUserState -> FormTransactionData -> m (C.Transaction, Signatures)
constructAndSignTransaction st FormTransactionData{..} = do
    () <$ updateBlockchain st False
    C.logInfo C.userLoggerName $
        format'
            "Form a transaction from {}, to {}, amount {}"
            ( listBuilderJSONIndent 2 $
              map
                  (\(a,b) ->
                        pairBuilder (a, listBuilderJSON b))
                  ftdInputs
            , ftdOutputAddress
            , listBuilderJSONIndent 2 $ ftdOutputCoins)
    when (nubBy ((==) `on` fst) ftdInputs /= ftdInputs) $
        commitError "All input addresses should have distinct indices."
    unless (all (> 0) $ concatMap snd ftdInputs) $
        commitError $
        formatSingle'
            "All input values should be positive, but encountered {}, that's not." $
        head $ filter (<= 0) $ concatMap snd ftdInputs
    accounts <- query' st GetAllAddresses
    let notInRange i = i >= genericLength accounts
    when (any notInRange $ map fst ftdInputs) $
        commitError $
        sformat
            ("Found an address id (" % int % ") that's not in [0 .. " % int %
             ")")
            (head $ filter notInRange $ map fst ftdInputs)
            (length accounts)
    let accInputs :: [(W.UserAddress, M.Map C.Color C.Coin)]
        accInputs =
            map
                (\(i,c) ->
                      (accounts `genericIndex` i, C.coinsToMap c))
                ftdInputs
        hasEnoughFunds :: (W.UserAddress, C.CoinsMap) -> m Bool
        hasEnoughFunds (acc,coinsMap) = do
            amountMap <- getAmountNoUpdate st acc
            let sufficient =
                    all
                        (\col0 ->
                              let weHave = M.findWithDefault 0 col0 amountMap
                                  weSpend = M.findWithDefault 0 col0 coinsMap
                              in weHave >= weSpend)
                        (M.keys coinsMap)
            return sufficient
    overSpentAccounts <- filterM (fmap not . hasEnoughFunds) accInputs
    unless (null overSpentAccounts) $
        commitError $
        (if length overSpentAccounts > 1
             then "At least the"
             else "The") <>
        formatSingle'
            " following account doesn't have enough coins: {}"
            (sel1 $ head overSpentAccounts)
    txPieces <-
        liftIO $
        mapM
            (uncurry (formTransactionMapper st ftdOutputCoins ftdOutputAddress))
            accInputs
    when (any isNothing txPieces) $
        commitError "Couldn't form transaction. Not enough funds."
    let (addrPairList,inputAddrids,outputs) =
            foldl1 pair3merge $ map fromJust txPieces
        outTr =
            C.Transaction
            { txInputs = inputAddrids
            , txOutputs = outputs ++ map (ftdOutputAddress, ) ftdOutputCoins
            }
        signatures =
            M.fromList $
            map
                (\(addrid',address') ->
                      (addrid', C.sign (address' ^. W.privateAddress) outTr))
                addrPairList
    when (not (null ftdOutputCoins) && not (C.validateSum outTr)) $
        commitError $
        formatSingle' "Your transaction doesn't pass validity check: {}" outTr
    when (null ftdOutputCoins && not (C.validateSum outTr)) $
        commitError $
        formatSingle'
            "Our code is broken and our auto-generated transaction is invalid: {}"
            outTr
    return (outTr, signatures)
  where
    pair3merge :: ([a], [b], [c]) -> ([a], [b], [c]) -> ([a], [b], [c])
    pair3merge = mappend

sendTransactionRetry
    :: forall m.
       WorkMode m
    => Word
    -> A.RSCoinUserState
    -> Maybe UserCache
    -> C.Transaction
    -> Signatures
    -> m ()
sendTransactionRetry tries st maybeCache tx signatures
  | tries < 1 =
      error
          "User.Operations.sendTransactionRetry shouldn't be called with tries < 1"
  | otherwise = sendTransactionDo st maybeCache tx signatures `catch` handler
  where
    handler :: SomeException -> m ()
    handler e
      | isRetriableException e && tries > 1 = logMsgAndRetry e
      | otherwise = throwM e
    logMsgAndRetry
        :: Buildable s
        => s -> m ()
    logMsgAndRetry msg = do
        C.logWarning C.userLoggerName $
            format'
                "Failed to send transaction ({}), retries left: {}"
                (msg, tries - 1)
        wait $ for 1 sec
        () <$ updateBlockchain st False
        sendTransactionRetry (tries - 1) st maybeCache tx signatures

sendTransactionDo
    :: forall m.
       WorkMode m
    => A.RSCoinUserState
    -> Maybe UserCache
    -> C.Transaction
    -> Signatures
    -> m ()
sendTransactionDo st maybeCache tx signatures = do
    C.logInfo C.userLoggerName $ sformat ("Sending transaction: " % build) tx
    walletHeight <- query' st A.GetLastBlockId
    lastBlockHeight <- pred <$> C.getBlockchainHeight
    when (walletHeight /= lastBlockHeight) $
        throwM $
        WalletSyncError $
        format'
            ("Wallet isn't updated (lastBlockHeight {} when blockchain's last block is {}). " <>
             "Please synchonize it with blockchain. The transaction wouldn't be sent.")
            (walletHeight, lastBlockHeight)
    validateTransaction maybeCache tx signatures $ lastBlockHeight + 1
    update' st $ A.AddTemporaryTransaction (lastBlockHeight + 1) tx

isRetriableException :: SomeException -> Bool
isRetriableException e
    | Just (_ :: UserLogicError) <- fromException e = True
    | Just MEInactive <- fromException e = True
    | isWalletSyncError e = True
    | otherwise = False

-- For given address and coins to send from it it returns a
-- pair. First element is chosen addrids with user addresses to
-- make signature map afterwards. The second is inputs of
-- transaction, third is change outputs
formTransactionMapper
    :: A.RSCoinUserState
    -> [C.Coin]
    -> C.Address
    -> W.UserAddress
    -> C.CoinsMap
    -> IO (Maybe ([(C.AddrId, W.UserAddress)], [C.AddrId], [(C.Address, C.Coin)]))
formTransactionMapper st outputCoin outputAddr address requestedCoins = do
    (addrids :: [C.AddrId]) <-
        concatMap (C.getAddrIdByAddress $ W.toAddress address) <$>
        query' st (A.GetTransactions address)
    let
        -- Pairs of chosen addrids and change for each color
        chosenMap0
            :: Maybe [([C.AddrId], C.Coin)]
        chosenMap0 = M.elems <$> C.chooseAddresses addrids requestedCoins
        chosenMap = fromJust chosenMap0
        -- All addrids from chosenMap
        inputAddrids = concatMap fst chosenMap
        -- Non-null changes (coins) from chosenMap
        changesValues
            :: [C.Coin]
        changesValues = filter (> 0) $ map snd chosenMap
        changes :: [(C.Address, C.Coin)]
        changes = map (W.toAddress address, ) changesValues
        autoGeneratedOutputs :: [(C.Address, C.Coin)]
        autoGeneratedOutputs
          | null outputCoin = map (outputAddr, ) $ C.coinsToList requestedCoins
          | otherwise = []
        retValue =
            ( map (, address) inputAddrids
            , inputAddrids
            , changes ++ autoGeneratedOutputs)
    return $ (const retValue) <$> chosenMap0
