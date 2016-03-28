{-# LANGUAGE TemplateHaskell #-}

-- | Protocol implements all low level communication between
-- entities (User, Bank, Mintette).

module RSCoin.Core.Protocol
       ( BankReq (..)
       , BankRes (..)
       , MintetteReq (..)
       , MintetteRes (..)
       , UserReq (..)
       , UserRes (..)
       , serve
       , callMintette
       , callBank
       , call
       , callBatch
       ) where

import           Network.JsonRpc       (BatchRequest (..), BatchResponse (..),
                                        ErrorObj, FromRequest (parseParams),
                                        FromResponse (parseResult), JsonRpcT,
                                        Respond, ToRequest (..), Ver (V2),
                                        buildResponse, fromError,
                                        jsonRpcTcpClient, jsonRpcTcpServer,
                                        receiveBatchRequest, sendBatchRequest,
                                        sendBatchResponse, sendRequest,
                                        sendResponse)

import           Control.Monad         (forM, liftM)
import           Control.Monad.Logger  (LoggingT, MonadLoggerIO, logDebug,
                                        runStderrLoggingT)
import           Control.Monad.Trans   (lift)
import           Data.Aeson            (FromJSON (parseJSON), ToJSON (toJSON))
import           Data.Aeson.Types      (Value (Array), emptyArray)
import qualified Data.ByteString.Char8 as BS
import           Data.Conduit.Network  (clientSettings, serverSettings)
import           Data.Foldable         (forM_)
import           Data.Maybe            (catMaybes)
import           Data.Vector           ((!?))

import           RSCoin.Core.Aeson     ()
import           RSCoin.Core.Constants (bankHost, bankPort)
import           RSCoin.Core.Types     (HBlock, Mintettes, NewPeriodData,
                                        PeriodId, PeriodResult, Mintette (..))

---- BANK data ----

-- | Request handled by Bank (probably sent by User or Mintette)
data BankReq
    = ReqGetMintettes
    | ReqGetBlockchainHeight
    | ReqGetHBlock PeriodId

instance FromRequest BankReq where
    parseParams "getMintettes" =
        Just $ const $ return ReqGetMintettes
    parseParams "getBlockchainHeight" =
        Just $ const $ return ReqGetBlockchainHeight
    parseParams "getHBlock" =
        Just $ \v -> ReqGetHBlock <$> do
            Array a <- parseJSON v
            maybe (fail "getHBLock: periodId not found") parseJSON $ a !? 0
    parseParams _ =
        Nothing

instance ToRequest BankReq where
    requestMethod ReqGetMintettes = "getMintettes"
    requestMethod ReqGetBlockchainHeight = "getBlockchainHeight"
    requestMethod (ReqGetHBlock _) = "getHBlock"
    requestIsNotif = const False

instance ToJSON BankReq where
    toJSON ReqGetMintettes = emptyArray
    toJSON ReqGetBlockchainHeight = emptyArray
    toJSON (ReqGetHBlock i) = toJSON [i]

-- | Responses to Bank requests (probably sent by User or Mintette)
data BankRes
    = ResGetMintettes Mintettes
    | ResGetBlockchainHeight Int
    | ResGetHBlock (Maybe HBlock)

instance FromResponse BankRes where
    parseResult "getMintettes" =
        Just $ fmap ResGetMintettes . parseJSON
    parseResult "getBlockchainHeight" =
        Just $ fmap ResGetBlockchainHeight . parseJSON
    parseResult "getHBlock" =
        Just $ fmap ResGetHBlock . parseJSON
    parseResult _ =
        Nothing

instance ToJSON BankRes where
    toJSON (ResGetMintettes ms) = toJSON ms
    toJSON (ResGetBlockchainHeight h) = toJSON h
    toJSON (ResGetHBlock h) = toJSON h

---- BANK data ----

---- MINTETTE data ----

-- | Request handled by Mintette (probably sent by User or Bank)
data MintetteReq
    = ReqPeriodFinished PeriodId
    | ReqAnnounceNewPeriod NewPeriodData

instance FromRequest MintetteReq where
    parseParams "periodFinished" =
        Just $ fmap ReqPeriodFinished . parseJSON
    parseParams "announceNewPeriod" =
        Just $ fmap ReqAnnounceNewPeriod . parseJSON
    parseParams _ =
        Nothing

instance ToRequest MintetteReq where
    requestMethod (ReqPeriodFinished _) = "periodFinished"
    requestMethod (ReqAnnounceNewPeriod _) = "announceNewPeriod"
    requestIsNotif = const False

instance ToJSON MintetteReq where
    toJSON (ReqPeriodFinished pid) = toJSON pid
    toJSON (ReqAnnounceNewPeriod npd) = toJSON npd

-- | Responses to Mintette requests (probably sent by User or Bank)
data MintetteRes
    = ResPeriodFinished PeriodResult
    | ResAnnounceNewPeriod

instance FromResponse MintetteRes where
    parseResult "periodFinished" =
        Just $ fmap ResPeriodFinished . parseJSON
    parseResult "announceNewPeriod" =
        Just $ const $ return ResAnnounceNewPeriod
    parseResult _ =
        Nothing

instance ToJSON MintetteRes where
    toJSON (ResPeriodFinished pid) = toJSON pid
    toJSON ResAnnounceNewPeriod = emptyArray

---- MINTETTE data ----

---- USER data ----

-- | Request handled by User (probably sent by Mintette or Bank)
data UserReq
    = ReqDummy

instance FromRequest UserReq where
    parseParams "dummy" =
        Just $ const $ return ReqDummy
    parseParams _ =
        Nothing

instance ToRequest UserReq where
    requestMethod ReqDummy = "dummy"
    requestIsNotif = const False

instance ToJSON UserReq where
    toJSON ReqDummy = emptyArray

-- | Responses to User requests (probably sent by Mintette or Bank)
data UserRes
    = ResDummy

instance FromResponse UserRes where
    parseResult "dummy" =
        Just $ const $ return ResDummy
    parseResult _ =
        Nothing

instance ToJSON UserRes where
    toJSON ResDummy = emptyArray

---- USER data ----

-- | Runs a TCP server transport for JSON-RPC.
serve :: (FromRequest a, ToJSON b) => Int -> (a -> IO b) -> IO ()
serve port handler = runStderrLoggingT $ do
    let ss = serverSettings port "::1"
    jsonRpcTcpServer V2 False ss . srv $ lift . liftM Right . handler

srv :: (MonadLoggerIO m, FromRequest a, ToJSON b) => Respond a m b -> JsonRpcT m ()
srv handler = do
    $(logDebug) "listening for new request"
    qM <- receiveBatchRequest
    case qM of
        Nothing -> do
            $(logDebug) "closed request channel, exting"
            return ()
        Just (SingleRequest q) -> do
            $(logDebug) "got request"
            rM <- lift $ buildResponse handler q
            forM_ rM sendResponse
            srv handler
        Just (BatchRequest qs) -> do
            $(logDebug) "got request batch"
            rs <- lift $ catMaybes `liftM` forM qs (buildResponse handler)
            sendBatchResponse $ BatchResponse rs
            srv handler

-- TODO: fix error handling
handleResponse :: Maybe (Either ErrorObj r) -> r
handleResponse t =
    case t of
        Nothing -> error "could not receive or parse response"
        Just (Left e) -> error $ fromError e
        Just (Right r) -> r

-- | Send a request to a Mintette.
callMintette :: (ToRequest a, ToJSON a, FromResponse b) => Mintette -> a -> IO b
callMintette Mintette {..} = call mintettePort mintetteHost

-- | Send a request to a Bank.
callBank :: (ToRequest a, ToJSON a, FromResponse b) => a -> IO b
callBank = call bankPort bankHost

-- TODO: improve logging
-- | Send a request.
call :: (ToRequest a, ToJSON a, FromResponse b) => Int -> String -> a -> IO b
call port host req = initCall port host $ do
    $(logDebug) "send a request"
    handleResponse <$> sendRequest req

-- | Send multiple requests in a batch.
callBatch :: (ToRequest a, ToJSON a, FromResponse b) => Int -> String -> [a] -> IO [b]
callBatch port host reqs = initCall port host $ do
    $(logDebug) "send a batch request"
    map handleResponse <$> sendBatchRequest reqs

-- | Runs a TCP client transport for JSON-RPC.
initCall :: Int -> String -> JsonRpcT (LoggingT IO) a -> IO a
initCall port host action = runStderrLoggingT $
    jsonRpcTcpClient V2 True (clientSettings port $ BS.pack host) action
