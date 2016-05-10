{-# LANGUAGE ExplicitForAll             #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE UndecidableInstances       #-}

module RSCoin.Timed.PureRpc
    ( PureRpc
    , runPureRpc
    , Delays(..)
    ) where

import           Control.Lens            (makeLenses, use, (%=), (.=))
import           Control.Monad           (forM_)
import           Control.Monad.Catch     (MonadCatch, MonadMask, MonadThrow)
import           Control.Monad.Random    (Rand, runRand)
import           Control.Monad.State     (MonadState (get, put, state), StateT,
                                          evalStateT, get, put)
import           Control.Monad.Trans     (MonadIO, MonadTrans, lift)
import           Data.Default            (Default, def)
import           Data.Map                as Map
import           Data.Maybe              (fromMaybe)
import           System.Random           (StdGen)

import           Data.MessagePack        (Object)
import           Data.MessagePack.Object (MessagePack, fromObject)

import           RSCoin.Timed.MonadRpc   (Addr, Client (..), Host, Method (..),
                                          MonadRpc, execClient, methodBody,
                                          methodName, serve)
import           RSCoin.Timed.MonadTimed (MicroSeconds, MonadTimed, for,
                                          localTime, mcs, sec, wait)
import           RSCoin.Timed.Timed      (TimedT, runTimedT)


data RpcStage = Request | Response

-- | Describes network nastyness
newtype Delays = Delays
    { -- | Just delay if net packet delivered successfully
      --   Nothing otherwise
      -- TODO: more parameters
      -- FIXME: we should handle StdGen with Quickcheck.Arbitrary
      evalDelay :: RpcStage -> MicroSeconds -> Rand StdGen (Maybe MicroSeconds)
      -- ^ I still think that this function is at right place
      --   We just need to find funny syntax for creating complex description
      --   of network nastinesses.
      --   Maybe like this one:
      {-
        delays $ do
                       during (10, 20) .= Probabitiy 60
            requests . before 30       .= Delay (5, 7)
            for "mintette2" $ do
                during (40, 150)       .= Probability 30 <> DelayUpTo 4
                responses . after 200  .= Disabled
      -}
      --   First what came to mind.
      --   Or maybe someone has overall better solution in mind
    }

instance Default Delays where
    -- | Descirbes reliable network
    def = Delays . const . const . return . Just $ 0

-- | Keeps servers' methods
type Listeners m = Map.Map (Addr, String) ([Object] -> m Object)

-- | Keeps global network information
data NetInfo m = NetInfo
    { _listeners :: Listeners m
    , _randSeed  :: StdGen
    , _delays    :: Delays
    }

$(makeLenses ''NetInfo)

-- | Pure implementation of RPC
newtype PureRpc m a = PureRpc
    { unwrapPureRpc :: StateT Host (TimedT (StateT (NetInfo (PureRpc m)) m)) a
    } deriving (Functor, Applicative, Monad, MonadIO, MonadTimed
               , MonadThrow, MonadCatch, MonadMask)

instance MonadTrans PureRpc where
    lift = PureRpc . lift . lift . lift

instance MonadState s m => MonadState s (PureRpc m) where
    get = lift get
    put = lift . put
    state = lift . state

-- | Launches rpc scenario
runPureRpc :: (Monad m, MonadCatch m) => StdGen -> Delays -> PureRpc m () -> m ()
runPureRpc _randSeed _delays (PureRpc rpc) =
    evalStateT (runTimedT (evalStateT rpc "127.0.0.1")) net
  where
    net        = NetInfo{..}
    _listeners = Map.empty

-- TODO: use normal exceptions here
request :: Monad m => MessagePack a => Client a -> (Listeners (PureRpc m), Addr) -> PureRpc m a
request (Client name args) (listeners', addr) =
    case Map.lookup (addr, name) listeners' of
        Nothing -> error $ mconcat
            ["Method ", name, " is not defined at ", show addr]
        Just f  -> fromMaybe (error "Answer type mismatch")
                 . fromObject <$> f args

instance (Monad m, MonadThrow m) => MonadRpc (PureRpc m) where
    execClient addr cli = PureRpc $ do
        curHost <- get
        unwrapPureRpc $ waitDelay Request

        ls <- lift . lift $ use listeners
        put $ fst addr
        answer <- unwrapPureRpc $ request cli (ls, addr)
        unwrapPureRpc $ waitDelay Response

        put curHost
        return answer

    serve port methods = PureRpc $ do
        host <- get
        lift $ lift $ forM_ methods $ \Method{..} ->
            listeners %= Map.insert ((host, port), methodName) methodBody

waitDelay :: MonadThrow m => RpcStage -> PureRpc m ()
waitDelay stage =
    PureRpc $
    do seed <- lift . lift $ use randSeed
       delays' <- lift . lift $ use delays
       time <- localTime
       let (delay,nextSeed) = runRand (evalDelay delays' stage time) seed
       lift $ lift $ randSeed .= nextSeed
       wait $ maybe (for 99999 sec) (`for` mcs) delay-- TODO: throw or eliminate
