{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE Rank2Types            #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE ViewPatterns          #-}

-- | This module contains time management monad and it's implementation for IO.
module RSCoin.Timed.MonadTimed
    ( fork, wait, localTime, workWhile, work, schedule, invoke, timeout
    , minute , sec , ms , mcs
    , minute', sec', ms', mcs'
    , tu
    , at, after, for, till, now
    , during, upto
    , interval
    , startTimer
    , Microsecond
    , Millisecond
    , Second
    , Minute
    , MonadTimed
    , RelativeToNow
    , MonadTimedError (..)
    ) where

import           Control.Exception    (Exception (..))
import           Control.Monad.Catch  (MonadThrow)
import           Control.Monad.Trans  (lift)
import           Control.Monad.Reader (ReaderT(..), runReaderT, ask)
import           Control.Monad.State  (StateT, evalStateT, get)

import           Data.Monoid          ((<>))
import           Data.Text            (Text)
import           Data.Text.Buildable  (Buildable (build))
import           Data.Time.Units      (TimeUnit (..), Microsecond, Millisecond,
                                       Second, Minute, convertUnit)
import           Data.Typeable        (Typeable)

import           RSCoin.Core.Error    (rscExceptionToException,
                                       rscExceptionFromException)

-- | Defines some time point (relative to current time point)
--   basing on current time point
type RelativeToNow = Microsecond -> Microsecond

data MonadTimedError
    = MTTimeoutError Text
    deriving (Show, Typeable)

instance Exception MonadTimedError where
    toException = rscExceptionToException
    fromException = rscExceptionFromException

instance Buildable MonadTimedError where
    build (MTTimeoutError t) = "timeout error: " <> build t

-- | Allows time management. Time is specified in microseconds passed
--   from start point (origin).
class MonadThrow m => MonadTimed m where
    -- | Acquires time relative to origin point
    localTime :: m Microsecond

    -- | Creates another thread of execution, with same point of origin
    fork :: m () -> m ()
    fork = workWhile $ return True

    -- | Waits till specified relative time
    wait :: RelativeToNow -> m ()

    -- | Forks a temporal thread, which exists
    --   until preficate evaluates to False
    workWhile :: m Bool -> m () -> m ()

    -- | Throws an TimeoutError exception if running an action exceeds running time
    timeout :: Microsecond -> m a -> m a

-- | Executes an action somewhere in future
schedule :: MonadTimed m => RelativeToNow -> m () -> m ()
schedule time action = fork $ wait time >> action

-- | Executes an action at specified time in current thread
invoke :: MonadTimed m => RelativeToNow -> m a -> m a
invoke time action = wait time >> action

-- | Like workWhile, unwraps first layer of monad immediatelly
--   and then checks predicate periocially
work :: MonadTimed m => TwoLayers m Bool -> m () -> m ()
work (getTL -> predicate) action = predicate >>= \p -> workWhile p action

instance MonadTimed m => MonadTimed (ReaderT r m) where
    localTime = lift localTime

    wait = lift . wait

    fork m = lift . fork . runReaderT m =<< ask

    workWhile p m =
        lift . (workWhile <$> runReaderT p <*> runReaderT m) =<< ask

    timeout t m = lift . timeout t . runReaderT m =<< ask

instance MonadTimed m => MonadTimed (StateT r m) where
    localTime = lift localTime

    wait = lift . wait

    fork m = lift . fork . evalStateT m =<< get

    workWhile p m =
        lift . (workWhile <$> evalStateT p <*> evalStateT m) =<< get

    timeout t m = lift . timeout t . evalStateT m =<< get

-- * Some usefull functions below

-- | Defines measure for time periods
mcs :: Microsecond -> Microsecond
mcs = convertUnit

ms :: Millisecond -> Microsecond
ms = convertUnit

sec :: Second -> Microsecond
sec = convertUnit

minute :: Minute -> Microsecond
minute = convertUnit

mcs', ms', sec', minute' :: Double -> Microsecond
mcs'    = fromMicroseconds . round
ms'     = fromMicroseconds . round . (*) 1000
sec'    = fromMicroseconds . round . (*) 1000000
minute' = fromMicroseconds . round . (*) 60000000

tu :: TimeUnit t => t -> Microsecond
tu = convertUnit

-- | Time point by given absolute time (still relative to origin)
at, till :: TimeAcc1 t => t
at   = at' 0
till = at' 0

-- | Time point relative to current time
after, for :: TimeAcc1 t => t
after = after' 0
for   = after' 0

-- | Current time point
now :: RelativeToNow
now = const 0

-- | Returns whether specified delay has passed
--   (timer starts when first monad layer is unwrapped)
during :: TimeAcc2 t => t
during = during' 0

-- | Returns whether specified time point has passed
upto :: TimeAcc2 t => t
upto = upto' 0

-- | Counts time since outer monad layer was unwrapped
startTimer :: MonadTimed m => m (m Microsecond)
startTimer = do
    start <- localTime
    return $ subtract start <$> localTime

-- | Returns a time in microseconds
--   Example: interval 1 sec :: Microsecond
interval :: TimeAcc3 t => t
interval = interval' 0


-- plenty of black magic
class TimeAcc1 t where
    at'    :: Microsecond -> t
    after' :: Microsecond -> t

instance TimeAcc1 RelativeToNow where
    at'    = (-)
    after' = const

instance (a ~ b, TimeAcc1 t) => TimeAcc1 (a -> (b -> Microsecond) -> t) where
    at'    acc t f = at'    $ f t + acc
    after' acc t f = after' $ f t + acc

-- without this newtype TimeAcc2 doesn't work - overlapping instances
newtype TwoLayers m a = TwoLayers { getTL :: m (m a) }

class TimeAcc2 t where
    during' :: Microsecond -> t
    upto'   :: Microsecond -> t

instance MonadTimed m => TimeAcc2 (TwoLayers m Bool) where
    during' time = TwoLayers $ do
        end <- (time + ) <$> localTime
        return $ (end > ) <$> localTime

    upto' time = TwoLayers . return $ (time > ) <$> localTime

instance (a ~ b, TimeAcc2 t) => TimeAcc2 (a -> (b -> Microsecond) -> t) where
    during' acc t f = during' $ f t + acc
    upto'   acc t f = upto'   $ f t + acc


class TimeAcc3 t where
    interval' :: Microsecond -> t

instance TimeAcc3 Microsecond where
    interval' = id

instance (a ~ b, TimeAcc3 t) => TimeAcc3 (a -> (b -> Microsecond) -> t) where
    interval' acc t f = interval' $ f t + acc

