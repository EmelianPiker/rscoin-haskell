{-# LANGUAGE ViewPatterns               #-}
{-# OPTIONS_GHC -fno-warn-type-defaults #-}

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
       , signHash
       , verify
       , verifyHash
       , keyGen
       ) where

import qualified Crypto.Hash.SHA256        as SHA256
import           Data.Binary               (Binary (put, get), encode)
import           Data.ByteString           (ByteString)
import qualified Data.ByteString.Base64    as B64
import           Data.Text.Buildable       (Buildable (build))
import qualified Data.Text.Format          as F

import           Test.QuickCheck.Arbitrary (arbitrary)
import           Test.QuickCheck.Gen       (generate)

import           Crypto.Secp256k1          (SecKey, PubKey, Sig,
                                           exportPubKey, importPubKey,
                                           importSig, exportSig, signMsg,
                                           msg, verifySig, derivePubKey)
-- | Hash is just a ByteString.
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
    return $ maybe (error "Signature import failed") Signature mSig
  put = put . exportSig . getSignature

newtype SecretKey =
  SecretKey { getSecretKey :: SecKey }
  deriving (Eq, Show)

newtype PublicKey =
  PublicKey { getPublicKey :: PubKey }
  deriving (Eq, Show)

instance Buildable PublicKey where
    build = build . F.Shown

instance Binary PublicKey where
  get = do
    mKey <- importPubKey <$> get
    return $ maybe (error "Public key import failed") PublicKey mKey
  put = put . exportPubKey True . getPublicKey

-- | Generate a hash from a binary data.
hash :: Binary t => t -> Hash
hash = Hash . B64.encode . SHA256.hashlazy . encode

-- | Generate a signature from a binary data.
sign :: Binary t => SecretKey -> t -> Signature
sign secKey = signHash secKey . hash

-- | Generate a signature from a hash data.
signHash :: SecretKey -> Hash -> Signature
signHash (getSecretKey -> secKey) =
  maybe
    (error "Message is too long")
    (Signature . signMsg secKey)
    . msg . getHash

-- | Verify signature from a binary message data.
verify :: Binary t => PublicKey -> Signature -> t -> Bool
verify pubKey sig = verifyHash pubKey sig . hash

-- | Verify signature from a hash message data.
verifyHash :: PublicKey -> Signature -> Hash -> Bool
verifyHash (getPublicKey -> pubKey) (getSignature -> sig) =
  maybe
    (error "Message is too long")
    (verifySig pubKey sig)
    . msg . getHash

-- | Generate arbitrary (secret key, public key) key pairs.
keyGen :: IO (SecretKey, PublicKey)
keyGen = do
  sKey <- generate arbitrary
  return (SecretKey sKey, PublicKey $ derivePubKey sKey)
