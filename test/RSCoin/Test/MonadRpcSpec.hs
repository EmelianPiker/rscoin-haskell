{-# LANGUAGE ViewPatterns #-}

-- | RSCoin.Test.MonadRpc specification

module RSCoin.Test.MonadRpcSpec
       ( spec
       ) where

import           Control.Concurrent.MVar     (newEmptyMVar, takeMVar, putMVar)
import           Control.Concurrent.Async    (race_)
import           Control.Monad.Trans         (liftIO, lift, MonadIO)
import           Data.MessagePack.Object     (Object(..), MessagePack, 
                                              toObject)
import qualified Data.Map                    as M
import           Data.Maybe                  (fromJust)
import           Numeric.Natural             (Natural)
import           Test.Hspec                  (Spec, describe)
import           Test.Hspec.QuickCheck       (prop)
import           Test.QuickCheck             (Arbitrary (arbitrary), 
                                             Property, ioProperty,
                                             counterexample, oneof, elements,
                                             NonEmptyList (..), Gen)
import           Test.QuickCheck.Function    (Fun, apply) 
import           Test.QuickCheck.Monadic     (run, assert, PropertyM, monadic,
                                             monitor, pick, forAllM)
import           Test.QuickCheck.Poly        (A)

import           RSCoin.Test.MonadRpc        (MonadRpc (..), Port, Host, Addr,
                                              Method (..), Client (..),
                                              MsgPackRpc (..))
import           RSCoin.Test.MonadTimed      (MonadTimed (..), runTimedIO, for, sec, work, during, ms, schedule, now, after)

import           Network.MessagePack.Server  (ServerT)
import           RSCoin.Test.MonadRpc

spec :: Spec
spec =
    describe "MonadRpc" $ do
        msgPackRpcSpec "MsgPackRpc" runMsgPackRpcProp

msgPackRpcSpec 
    :: (MonadRpc m, MonadTimed m, MonadIO m)
    => String
    -> (PropertyM m () -> Property)
    -> Spec
msgPackRpcSpec description runProp =
    describe description $ do
        describe "server method should execute" $ do
            prop "client should be able to execute server method" $
                runProp serverMethodShouldExecuteSimpleSpec
        describe "server method should execute" $ do
            prop "client should be able to execute server method" $
                runProp . serverMethodShouldExecuteSpec

runMsgPackRpcProp :: PropertyM MsgPackRpc () -> Property
runMsgPackRpcProp = monadic $ ioProperty . runTimedIO . runMsgPackRpc

-- TODO: it would be useful to create an instance of Function for Client and Method;
-- see here https://hackage.haskell.org/package/QuickCheck-2.8.2/docs/Test-QuickCheck-Function.html#t:Function

port :: Port
port = 5000

host :: Host
host = "127.0.0.1"

addr :: Addr
addr = (host, port)

serverMethodShouldExecuteSimpleSpec
    :: (MonadTimed m, MonadRpc m, MonadIO m)
    => PropertyM m ()
serverMethodShouldExecuteSimpleSpec = do
    run $ fork $ server
    client

server :: MonadRpc m => m ()
server = do
    let respAdd = add
        respEcho = echo
    restrict $ respAdd 0 0
    restrict $ respEcho ""
    serve port
        [ method "add"  respAdd
        , method "echo" respEcho
        ]
  where
    add :: Monad m => Int -> Int -> ServerT m Int
    add x y = return $ x + y

    echo :: Monad m => String -> ServerT m String
    echo s = return $ "***" ++ s ++ "***"

restrict :: Monad m => ServerT m a -> m ()
restrict _  =  return ()

client :: (MonadRpc m, MonadTimed m) => PropertyM m ()
client = do
	run $ wait $ for 1 sec
	r1 <- run $ execClient addr $ add 123 456
	assert $ r1 == 123 + 456
	r2 <- run $ execClient addr $ echo "hello"
	assert $ r2 == "***hello***"
  where
    add :: Int -> Int -> Client Int
    add = call "add"

    echo :: String -> Client String
    echo = call "echo"

-- | Method should execute if called correctly
serverMethodShouldExecuteSpec
    :: (MonadTimed m, MonadRpc m)
    => NonEmptyList (NonEmptyList Char)
    -> PropertyM m ()
serverMethodShouldExecuteSpec (getNonEmpty -> methodNames') = do
    mtds <- createMethods methodNames
    let methodMap = createMethodMap mtds
    run . fork $ serve port mtds
    run . wait $ for 500 ms
    name <- pick $ elements methodNames
    res <- run . execClient addr $ Client name []
    shouldBe <- run $ fromJust $ M.lookup name methodMap <*> pure []
    assert $ shouldBe == res
  where methodNames = map getNonEmpty methodNames'
        -- TODO: we wouldn't need to do this if Function was defined
        createMethods :: Monad m => [String] -> PropertyM m [Method m]
        createMethods = mapM $ \name -> do
            res <- toObject <$> pick (arbitrary :: Gen Int)
            return . Method name . const $ return res
        createMethodMap = M.fromList . map (\m -> (methodName m, methodBody m))
