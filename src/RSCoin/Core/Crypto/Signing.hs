{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ViewPatterns    #-}

-- | Signing-related functions and types.

module RSCoin.Core.Crypto.Signing
       ( Signature
       , SecretKey
       , PublicKey
       , sign
       , verify
       , keyGen
       , constructPublicKey
       , writePublicKey
       , readPublicKey
       , constructSecretKey
       , writeSecretKey
       , readSecretKey
       , derivePublicKey
       , checkKeyPair
       ) where

import qualified Crypto.Sign.Ed25519        as E
import           Data.Bifunctor             (bimap)
import           Data.Binary                (Binary (get, put), decodeOrFail,
                                             encode)
import qualified Data.ByteString            as BS
import qualified Data.ByteString.Base64     as B64
import           Data.Hashable              (Hashable (hashWithSalt))
import           Data.Maybe                 (fromMaybe)
import           Data.MessagePack           (MessagePack (toObject, fromObject))
import           Data.SafeCopy              (Contained,
                                             SafeCopy (getCopy, putCopy),
                                             contain, safeGet, safePut)
import           Data.Serialize             (Get, Put)
import           Data.Text                  (Text)
import           Data.Text.Buildable        (Buildable (build))
import           Data.Text.Encoding         (decodeUtf8, encodeUtf8)
import qualified Data.Text.Format           as F
import qualified Data.Text.IO               as TIO
import           Data.Tuple                 (swap)
import           System.Directory           (createDirectoryIfMissing)
import           System.FilePath            (takeDirectory)
import           Test.QuickCheck            (Arbitrary (arbitrary), vector)

import           Serokell.Util.Exceptions   (throwText)
import           Serokell.Util.Text         (show')

import qualified RSCoin.Core.Crypto.Hashing as H

newtype Signature = Signature
    { getSignature :: E.Signature
    } deriving (Eq,Show)

putCopyBinary :: Binary a => a -> Contained Put
putCopyBinary = contain . safePut . encode

getCopyBinary :: Binary a => Contained (Get a)
getCopyBinary =
    contain $
    do bs <- safeGet
       either onError onSuccess . decodeOrFail $ bs
  where
    onError (_,_,errMsg) = fail errMsg
    onSuccess (_,_,res) = return res

instance SafeCopy Signature where
    putCopy = putCopyBinary
    getCopy = getCopyBinary

instance Buildable Signature where
    -- Feel free to change it if you need actual Signature
    -- build = build . F.Shown . getSignature
    build _ = "Signature"

instance MessagePack Signature where
    toObject = toObject . E.unSignature . getSignature
    fromObject obj = Signature . E.Signature <$> fromObject obj

instance Binary Signature where
    get = Signature . E.Signature <$> get
    put = put . E.unSignature . getSignature

newtype SecretKey = SecretKey
    { getSecretKey :: E.SecretKey
    } deriving (Eq, Show, Ord)

instance Buildable SecretKey where
    build = build . F.Shown . getSecretKey

instance Binary SecretKey where
    get = SecretKey . E.SecretKey <$> get
    put = put . E.unSecretKey . getSecretKey

instance SafeCopy SecretKey where
    putCopy = putCopyBinary
    getCopy = getCopyBinary

instance Arbitrary SecretKey where
    arbitrary =
        SecretKey .
        snd .
        fromMaybe (error "createKeypairFromSeed_ failed") .
        E.createKeypairFromSeed_ . BS.pack <$>
        vector 32

newtype PublicKey = PublicKey
    { getPublicKey :: E.PublicKey
    } deriving (Eq, Show, Ord)

instance Buildable PublicKey where
    build = build . decodeUtf8 . B64.encode . E.unPublicKey . getPublicKey

instance Hashable PublicKey where
    hashWithSalt s = hashWithSalt s . E.unPublicKey . getPublicKey

instance Binary PublicKey where
    get = PublicKey . E.PublicKey <$> get
    put = put . E.unPublicKey . getPublicKey

instance SafeCopy PublicKey where
    putCopy = putCopyBinary
    getCopy = getCopyBinary

instance MessagePack PublicKey where
    toObject = toObject . E.unPublicKey . getPublicKey
    fromObject = fmap (PublicKey . E.PublicKey) . fromObject

instance Arbitrary PublicKey where
    arbitrary = derivePublicKey <$> arbitrary

-- | Sign a serializable value.
sign :: Binary t => SecretKey -> t -> Signature
sign (getSecretKey -> secKey) =
    Signature . E.dsign secKey . H.getHash . H.hash . encode

-- | Verify signature for a serializable value.
verify :: Binary t => PublicKey -> Signature -> t -> Bool
verify (getPublicKey -> pubKey) (getSignature -> sig) t =
    E.dverify pubKey (H.getHash . H.hash $ encode t) sig

-- | Generate arbitrary (secret key, public key) key pair.
keyGen :: IO (SecretKey, PublicKey)
keyGen = bimap SecretKey PublicKey . swap <$> E.createKeypair

-- | Constructs public key from UTF-8 text.
constructPublicKey :: Text -> Maybe PublicKey
constructPublicKey (encodeUtf8 -> s) =
    case B64.decode s of
        Left _ -> Nothing
        Right t -> Just $ PublicKey $ E.PublicKey t

-- | Write PublicKey to a file.
writePublicKey :: FilePath -> PublicKey -> IO ()
writePublicKey fp k = do
    ensureDirectoryExists fp
    TIO.writeFile fp $ show' k

-- | Read PublicKey from a file.
readPublicKey :: FilePath -> IO PublicKey
readPublicKey fp =
    maybe (throwText "Failed to parse public key") return =<<
    (constructPublicKey <$> TIO.readFile fp)

-- | Write SecretKey to a file.
writeSecretKey :: FilePath -> SecretKey -> IO ()
writeSecretKey fp (E.unSecretKey . getSecretKey -> k) = do
    ensureDirectoryExists fp
    BS.writeFile fp k

-- | Read SecretKey from a file.
readSecretKey :: FilePath -> IO SecretKey
readSecretKey file = SecretKey . E.SecretKey <$> BS.readFile file

-- | Construct secret key from file content.
-- In general it should not be used.  The only reason it's needed is
-- to read embeded key (for which we know it's correct).
constructSecretKey :: BS.ByteString -> SecretKey
constructSecretKey = SecretKey . E.SecretKey

ensureDirectoryExists :: FilePath -> IO ()
ensureDirectoryExists (takeDirectory -> d) =
    createDirectoryIfMissing True d

-- | Derive public key from the secret key
derivePublicKey :: SecretKey -> PublicKey
derivePublicKey (getSecretKey -> sk) =
    PublicKey $ E.toPublicKey sk

-- | Validate the sk to be the secret key of pk
checkKeyPair :: (SecretKey, PublicKey) -> Bool
checkKeyPair (sk, pk) = pk == derivePublicKey sk
