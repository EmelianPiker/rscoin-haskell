{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE TemplateHaskell        #-}

-- | Context to run full rscoin system.

module Test.RSCoin.Full.Context
       ( BankInfo (..)
       , MintetteInfo (..)
       , UserInfo (..)
       , Scenario (..)
       , TestContext (..)
       , TestEnv
       , MintetteNumber (..), UserNumber (..)
       , bank, mintettes, buser, users, scenario
       , keys, secretKey, publicKey
       , state
       , port
       ) where

import           Control.Lens         (Getter, makeLenses, to, _1, _2)
import           Control.Monad.Reader (ReaderT)
import           Data.Word            (Word16, Word8)

import qualified RSCoin.Bank          as B
import           RSCoin.Core          (PublicKey, SecretKey, bankPort)
import qualified RSCoin.Mintette      as M
import qualified RSCoin.User          as U

-- | Number of mintettes in system.
newtype MintetteNumber = MintetteNumber
    { getMintetteNumber :: Word8
    } deriving (Show,Real,Ord,Eq,Enum,Num,Integral)

-- | Number of users in system.
newtype UserNumber = UserNumber
    { getUserNumber :: Word16
    } deriving (Show,Real,Ord,Eq,Enum,Num,Integral)

data BankInfo = BankInfo
    { _bankKeys  :: (SecretKey, PublicKey)
    , _bankState :: B.State
    }

$(makeLenses ''BankInfo)

data MintetteInfo = MintetteInfo
    { _mintetteKeys  :: (SecretKey, PublicKey)
    , _mintetteState :: M.State
    , _mintettePort  :: Int
    }

$(makeLenses ''MintetteInfo)

data UserInfo = UserInfo
    { _userState :: U.RSCoinUserState
    }

$(makeLenses ''UserInfo)

-- also mixed?
data Scenario
    = DefaultScenario                -- ^ Default behaviour of all nodes
    | MalfunctioningMintettes Double -- ^ Some mintette fraction makes errors
    | AdversarialMintettes Double    -- ^ Mintettes try to execute malicious actions
    deriving (Show)

data TestContext = TestContext
    { _bank      :: BankInfo
    , _mintettes :: [MintetteInfo]
    , _buser     :: UserInfo  -- ^ user in bank mode
    , _users     :: [UserInfo]
    , _scenario  :: Scenario
    }

$(makeLenses ''TestContext)

type TestEnv m = ReaderT TestContext m

-- * Shortcuts

class WithKeys w where
    keys :: Getter w (SecretKey, PublicKey)

secretKey :: WithKeys w => Getter w SecretKey
secretKey = keys . _1

publicKey :: WithKeys w => Getter w PublicKey
publicKey = keys . _2

instance WithKeys BankInfo where
    keys = bankKeys

instance WithKeys MintetteInfo where
    keys = mintetteKeys

class WithState w s | w -> s where
    state :: Getter w s

instance WithState BankInfo B.State where
    state = bankState

instance WithState MintetteInfo M.State where
    state = mintetteState

instance WithState UserInfo U.RSCoinUserState where
    state = userState


class WithPort w where
    port :: Getter w Int

instance WithPort BankInfo where
    port = to $ const bankPort

instance WithPort MintetteInfo where
    port = mintettePort
