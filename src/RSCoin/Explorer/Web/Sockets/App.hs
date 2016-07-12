{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE Rank2Types            #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}

-- | Logic of Explorer WebSockets Server.

module RSCoin.Explorer.Web.Sockets.App
       ( wsLoggerName
       , mkWsApp
       ) where

import           Control.Concurrent                (forkIO)
import           Control.Concurrent.MVar           (MVar, modifyMVar, newMVar,
                                                    readMVar)
import           Control.Lens                      (at, makeLenses, use, view,
                                                    (%=), (+=), (.=), (^.))
import           Control.Monad                     (forever)
import           Control.Monad.Catch               (Handler (Handler),
                                                    SomeException, catches,
                                                    finally)
import           Control.Monad.Reader              (ReaderT, runReaderT)
import           Control.Monad.State               (MonadState, State, runState)
import           Control.Monad.Trans               (MonadIO (liftIO))
import           Data.Acid.Advanced                (query')
import qualified Data.Map.Strict                   as M
import           Data.Maybe                        (catMaybes, fromMaybe)
import qualified Data.Set                          as S
import           Data.Text                         (Text)
import           Data.Time.Units                   (Second)
import           Formatting                        (build, int, sformat, shown,
                                                    (%))
import qualified Network.WebSockets                as WS

import           Serokell.Util.Concurrent          (threadDelay)
import           Serokell.Util.Text                (listBuilderJSON)

import qualified RSCoin.Core                       as C

import qualified RSCoin.Explorer.AcidState         as DB
import           RSCoin.Explorer.Channel           (Channel, ChannelItem (..),
                                                    readChannel)
import           RSCoin.Explorer.Web.Sockets.Types (AddressInfoMsg (..),
                                                    ErrorableMsg,
                                                    IntroductoryMsg (..),
                                                    OutcomingMsg (..),
                                                    mkOMBalance)

type ConnectionId = Word

data ConnectionsState = ConnectionsState
    { _csCounter      :: !Word
    , _csIdToConn     :: !(M.Map ConnectionId WS.Connection)
    , _csAddrToConnId :: !(M.Map C.Address (S.Set ConnectionId))
    }

$(makeLenses ''ConnectionsState)

addConnection
    :: MonadState ConnectionsState m
    => C.Address -> WS.Connection -> m ConnectionId
addConnection addr conn = do
    i <- use csCounter
    csCounter += 1
    csIdToConn . at i .= Just conn
    csAddrToConnId . at addr %= Just . (maybe (S.singleton i) (S.insert i))
    return i

dropConnection
    :: MonadState ConnectionsState m
    => C.Address -> ConnectionId -> m ()
dropConnection addr connId = do
    csIdToConn . at connId .= Nothing
    csAddrToConnId . at addr %= fmap (S.delete connId)

type ConnectionsVar = MVar ConnectionsState

data ServerState = ServerState
    { _ssDataBase    :: DB.State
    , _ssConnections :: ConnectionsVar
    }

mkConnectionsState :: ConnectionsState
mkConnectionsState =
    ConnectionsState
    { _csCounter = 0
    , _csIdToConn = M.empty
    , _csAddrToConnId = M.empty
    }

modifyConnectionsState
    :: MonadIO m
    => ConnectionsVar -> State ConnectionsState a -> m a
modifyConnectionsState var st =
    liftIO $ modifyMVar var (pure . swap . runState st)
  where
    swap (a,b) = (b, a)

$(makeLenses ''ServerState)

type ServerMonad = ReaderT ServerState IO

send
    :: MonadIO m
    => WS.Connection -> OutcomingMsg -> m ()
send conn = liftIO . WS.sendTextData conn

recv
    :: (MonadIO m, WS.WebSocketsData (ErrorableMsg msg))
    => WS.Connection -> (msg -> m ()) -> m ()
recv conn callback =
    either (send conn . OMError) callback =<<
    liftIO (WS.receiveData conn)

wsLoggerName :: C.LoggerName
wsLoggerName = "explorer WS"

logError, logInfo, logDebug
    :: MonadIO m
    => Text -> m ()
logError = C.logError wsLoggerName
logInfo = C.logInfo wsLoggerName
logDebug = C.logDebug wsLoggerName

handler :: WS.PendingConnection -> ServerMonad ()
handler pendingConn = do
    logDebug "There is a new pending connection"
    conn <- liftIO $ WS.acceptRequest pendingConn
    logDebug "Accepted new connection"
    liftIO $ WS.forkPingThread conn 30
    recv conn $ onReceive conn
  where
    onReceive conn (IMAddressInfo addr) = do
        connections <- view ssConnections
        connId <- modifyConnectionsState connections $ addConnection addr conn
        logInfo $
            sformat
                ("Session about " % build %
                 " is established, connection id is " %
                 int)
                addr
                connId
        addressInfoHandler addr conn `finally`
            modifyConnectionsState connections (dropConnection addr connId)

addressInfoHandler :: C.Address -> WS.Connection -> ServerMonad ()
addressInfoHandler addr conn = forever $ recv conn onReceive
  where
    onReceive AIGetBalance = do
        logDebug $ sformat ("Balance of " % build % " is requested") addr
        send conn . uncurry mkOMBalance =<<
            flip query' (DB.GetAddressBalance addr) =<< view ssDataBase
    onReceive AIGetTxNumber = do
        logDebug $
            sformat
                ("Number of transactions pointing to " % build %
                 " is requested")
                addr
        send conn . uncurry OMTxNumber =<<
            flip query' (DB.GetAddressTxNumber addr) =<< view ssDataBase
    onReceive (AIGetTransactions indices@(lo,hi)) = do
        logDebug $
            sformat
                ("Transactions [" % int % ", " % int % "] pointing to " % build %
                 " are requested")
                lo
                hi
                addr
        send conn . uncurry OMTransactions =<<
            flip query' (DB.GetAddressTransactions addr indices) =<<
            view ssDataBase

sender :: Channel -> ServerMonad ()
sender channel =
    foreverSafe $
    do ChannelItem{ciTransactions = txs} <- readChannel channel
       logDebug "There is a new ChannelItem in Channel"
       st <- view ssDataBase
       let inputs = concatMap C.txInputs txs
           outputs = concatMap C.txOutputs txs
           outputAddresses = S.fromList $ map fst outputs
           inputToAddr
               :: MonadIO m
               => C.AddrId -> m (Maybe C.Address)
           inputToAddr (txId,idx,_) =
               fmap (fst . (!! idx) . C.txOutputs) <$>
               query' st (DB.GetTx txId)
       affectedAddresses <-
           mappend outputAddresses . S.fromList . catMaybes <$>
           mapM inputToAddr inputs
       logDebug $
           sformat
               ("Affected addresses are: " % build)
               (listBuilderJSON affectedAddresses)
       mapM_ notifyAboutAddressUpdate affectedAddresses
  where
    foreverSafe :: ServerMonad () -> ServerMonad ()
    foreverSafe action = do
        let catchConnectionError :: WS.ConnectionException -> ServerMonad ()
            catchConnectionError e =
                logError $ sformat ("Connection error happened: " % shown) e
            catchWhateverError :: SomeException -> ServerMonad ()
            catchWhateverError e = do
                logError $ sformat ("Strange error happened: " % shown) e
                threadDelay (2 :: Second)
        action `catches`
            [Handler catchConnectionError, Handler catchWhateverError]
        foreverSafe action

notifyAboutAddressUpdate :: C.Address -> ServerMonad ()
notifyAboutAddressUpdate addr = do
    st <- view ssDataBase
    connectionsState <- liftIO . readMVar =<< view ssConnections
    msgBalance <- uncurry mkOMBalance <$> query' st (DB.GetAddressBalance addr)
    msgTxNumber <-
        uncurry OMTxNumber <$> query' st (DB.GetAddressTxNumber addr)
    let connIds =
            fromMaybe S.empty $ connectionsState ^. csAddrToConnId . at addr
        idToConn i = connectionsState ^. csIdToConn . at i
        foldrStep connId l = maybe l (: l) $ idToConn connId
        connections = S.foldr foldrStep [] connIds
        sendToAll msg = mapM_ (flip send msg) connections
    mapM_ sendToAll [msgBalance, msgTxNumber]

-- | Given access to Explorer's data base and channel, returns
-- WebSockets server application.
mkWsApp
    :: MonadIO m
    => Channel -> DB.State -> m WS.ServerApp
mkWsApp channel st =
    liftIO $
    do connections <- newMVar mkConnectionsState
       let ss =
               ServerState
               { _ssDataBase = st
               , _ssConnections = connections
               }
           app pc = runReaderT (handler pc) ss
       app <$ forkIO (runReaderT (sender channel) ss)
