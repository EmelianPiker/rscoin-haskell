{-# LANGUAGE PatternGuards #-}

module Bench.RSCoin.UserLogic
        ( benchUserTransactions
        , initializeBank
        , initializeUser
        , userThread
        , runSingleUser
        ) where

import           Control.Monad              (forM_, when)
import           Control.Monad.Catch        (bracket)
import           Control.Monad.Trans        (liftIO)
import           Data.Acid                  (createCheckpoint)
import           Data.Acid.Advanced         (query')
import           Data.ByteString            (ByteString)
import           Data.Int                   (Int64)
import           Formatting                 (int, sformat, (%))
import           System.FilePath            ((</>))

import           RSCoin.Core                (Address (..), Coin (..),
                                             bankSecretKey, finishPeriod,
                                             keyGen)

import           RSCoin.Timed               (MsgPackRpc, for, runRealMode, sec,
                                             wait)
import qualified RSCoin.User.AcidState      as A
import           RSCoin.User.Cache          (UserCache, mkUserCache)
import           RSCoin.User.Operations     (formTransactionRetry)
import           RSCoin.User.Wallet         (UserAddress)

import           Bench.RSCoin.FilePathUtils (dbFormatPath)
import           Bench.RSCoin.Logging       (logDebug, logInfo)

userThread
    :: ByteString
    -> FilePath
    -> (Word -> A.RSCoinUserState -> MsgPackRpc a)
    -> Word
    -> IO a
userThread bankHost benchDir userAction userId =
    runRealMode bankHost $
    bracket
        (liftIO $ A.openState $ benchDir </> dbFormatPath "wallet-db" userId)
        (\userState ->
              liftIO $
              do createCheckpoint userState
                 A.closeState userState)
        (userAction userId)

queryMyAddress :: A.RSCoinUserState -> MsgPackRpc UserAddress
queryMyAddress userState = head <$> query' userState A.GetAllAddresses

-- | Create user with 1 address and return it.
initializeUser :: Word -> A.RSCoinUserState -> MsgPackRpc UserAddress
initializeUser userId userState = do
    let userAddressesNumber = 1
    logDebug $ sformat ("Initializing user " % int % "…") userId
    A.initState userState userAddressesNumber Nothing
    queryMyAddress userState <*
        logDebug (sformat ("Initialized user " % int % "…") userId)

executeTransaction :: A.RSCoinUserState
                   -> UserCache
                   -> Int64
                   -> Address
                   -> MsgPackRpc ()
executeTransaction userState cache coinAmount addrToSend =
    () <$
    formTransactionRetry
        maxBound
        userState
        (Just cache)
        False
        inputMoneyInfo
        addrToSend
        outputMoney
  where
    outputMoney = Coin coinAmount
    inputMoneyInfo = [(1, outputMoney)]

-- | Create user in `bankMode` and send coins to every user.
initializeBank :: Word -> [Address] -> A.RSCoinUserState -> MsgPackRpc ()
initializeBank coinsNum userAddresses bankUserState = do
    logInfo "Initializaing user in bankMode…"
    let additionalBankAddreses = 0
    logDebug "Before initStateBank"
    A.initStateBank bankUserState additionalBankAddreses bankSecretKey
    logDebug "After initStateBank"
    cache <- liftIO mkUserCache
    forM_ userAddresses $
        executeTransaction bankUserState cache (fromIntegral coinsNum)
    logDebug "Sent initial coins from bank to users"
    logInfo
        "Initialized user in bankMode, finishing period"
    finishPeriod bankSecretKey
    wait $ for 1 sec

-- | Do `txNum` transactions to random address.
benchUserTransactions :: Word
                      -> Word
                      -> A.RSCoinUserState
                      -> MsgPackRpc ()
benchUserTransactions txNum userId userState = do
    let loggingStep = txNum `div` 5
    addr <- Address . snd <$> liftIO keyGen
    cache <- liftIO mkUserCache
    forM_ [0 .. txNum - 1] $
        \i ->
             do when (i /= 0 && i `mod` loggingStep == 0) $
                    logInfo $
                    sformat
                        ("User " % int % " has executed " % int %
                         " transactions")
                        userId
                        i
                executeTransaction userState cache 1 addr

runSingleUser :: Word -> A.RSCoinUserState -> MsgPackRpc ()
runSingleUser txNum bankUserState = do
    address <- Address . snd <$> liftIO keyGen
    let additionalBankAddreses = 0
    logDebug "Before initStateBank"
    A.initStateBank bankUserState additionalBankAddreses bankSecretKey
    logDebug "After initStateBank"
    cache <- liftIO mkUserCache
    forM_ [1 .. txNum] $
        \i ->
             do executeTransaction bankUserState cache 1 address
                when (i `mod` (txNum `div` 5) == 0) $
                    logInfo $ sformat ("Executed " % int % " transactions") i
