{-# LANGUAGE ViewPatterns #-}

-- | A small module providing necessary cryptographic functions
-- We are using secp256k1 implementation.
-- For more see wiki https://en.bitcoin.it/wiki/Secp256k1
module RSCoin.Core.Crypto
       ( Hash
       , getHash
       , Signature
       , SecretKey
       , PublicKey
       , hash
       , sign
       , verify
       , keyGen
       ) where

import qualified Crypto.Hash.SHA256        as SHA256
import           Data.Binary               (Binary (put, get), decodeOrFail,
                                            encode)
import           Data.ByteString           (ByteString)
import qualified Data.ByteString.Base64    as B64
import           Data.SafeCopy             (SafeCopy (putCopy, getCopy),
                                            contain, safeGet, safePut)
import           Data.Text.Buildable       (Buildable (build))
import qualified Data.Text.Format          as F

import           Test.QuickCheck.Arbitrary (arbitrary)
import           Test.QuickCheck.Gen       (generate)

import           Crypto.Secp256k1          (Msg, PubKey, SecKey, Sig,
                                            derivePubKey, exportPubKey,
                                            exportSig, importPubKey, importSig,
                                            msg, signMsg, verifySig)

-- | Hash is just a base64 encoded ByteString.
newtype Hash =
    Hash { getHash :: ByteString }
    deriving (Eq, Show, Binary)

instance Buildable Hash where
    build = build . F.Shown

newtype Signature =
    Signature { getSignature :: Sig }
    deriving (Eq, Show)

instance Buildable Signature where
    build = build . F.Shown

instance Binary Signature where
    get = do
        mSig <- importSig <$> get
        maybe (fail "Signature import failed") (return . Signature) mSig
    put = put . exportSig . getSignature

newtype SecretKey =
    SecretKey { getSecretKey :: SecKey }
    deriving (Eq, Show)

newtype PublicKey =
    PublicKey { getPublicKey :: PubKey }
    deriving (Eq, Show)

instance SafeCopy PublicKey where
    putCopy = contain . safePut . encode
    getCopy =
        contain $
        do bs <- safeGet
           either onError onSuccess . decodeOrFail $ bs
      where
        onError (_,_,errMsg) = fail errMsg
        onSuccess (_,_,res) = return res

instance Buildable PublicKey where
    build = build . F.Shown

instance Binary PublicKey where
    get = do
        mKey <- importPubKey <$> get
        maybe (fail "Public key import failed") (return . PublicKey) mKey
    put = put . exportPubKey True . getPublicKey

-- | Generate a hash from a binary data.
hash :: Binary t => t -> Hash
hash = Hash . B64.encode . SHA256.hashlazy . encode

-- | Generate a signature from a binary data.
sign :: Binary t => SecretKey -> t -> Signature
sign (getSecretKey -> secKey) =
    withBinaryHashedMsg $
        Signature . signMsg secKey

-- | Verify signature from a binary message data.
verify :: Binary t => PublicKey -> Signature -> t -> Bool
verify (getPublicKey -> pubKey) (getSignature -> sig) =
    withBinaryHashedMsg $
        verifySig pubKey sig

-- | Generate arbitrary (secret key, public key) key pairs.
keyGen :: IO (SecretKey, PublicKey)
keyGen = do
    sKey <- generate arbitrary
    return (SecretKey sKey, PublicKey $ derivePubKey sKey)

withBinaryHashedMsg :: Binary t => (Msg -> a) -> t -> a
withBinaryHashedMsg action =
    maybe
        (error "Message is too long") -- NOTE: this shouldn't ever happen
                                      -- becouse SHA256.hashlazy encodes
                                      -- messages in 32 bytes
        action
        . msg . SHA256.hashlazy . encode
