{-# LANGUAGE CPP #-}
-- | Command line options interface for user

module UserOptions
       ( UserOptions (..)
       , UserCommand (..)
       , DumpCommand (..)
       , getUserOptions
       ) where

import           Control.Applicative    (optional)
import           Data.Int               (Int64)
import           Data.Monoid            ((<>))
import           Data.Text              (Text)
import           Options.Applicative    (Parser, argument, auto, command,
                                         execParser, fullDesc, help, helper,
                                         info, long, many, metavar, option,
                                         progDesc, short, showDefault, some,
                                         subparser, switch, value)
import           System.FilePath        ((</>))

import           Serokell.Util.OptParse (strOption)

import           RSCoin.Core            (MintetteId, PeriodId, Severity (Info),
                                         configDirectory, defaultAccountsNumber,
                                         defaultConfigurationPath,
                                         defaultSecretKeyPath)
import           RSCoin.User            (UserCache)


-- | Command that describes single action from command-line interface
-- POV
data UserCommand
    -- | List all addresses in wallet, starting with 1
    = ListAddresses
    -- | Query bank to update wallet state according to blockchain
    -- status
    | UpdateBlockchain
    -- | First argument represents inputs -- pairs (a,b,c), where a is
    -- index (starting from 1) of address in wallet, b is positive
    -- integer representing value to send. c is color.  Second
    -- argument represents the address to send, and amount. Forth
    -- argument is optional cache
    | FormTransaction [(Word, Int64, Int)]
                      Text
                      [(Int64, Int)]
                      (Maybe UserCache)
    -- | Initialize multisignature address allocation.
    -- 1. Number m of required signatures from addr;
    -- 2. List of user parties in addresses;
    -- 3. List of trust parties in addresses;
    -- 4. Master public key;
    -- 5. Signature of slave key with master key.
    | CreateMultisigAddress Int
                            [Text]
                            [Text]
                            (Maybe Text)
                            (Maybe Text)

    -- | List all addresses in which current user acts like party.
    -- Specify trust public key if you also want to receive MS addresses
    -- with trust as party.
    | ListAllocations (Maybe Text)
    -- | List all allocations in the blacklist
    | ListAllocationsBlacklist (Maybe Text)
    -- | Put an allocation into blacklist and ignore it
    | BlacklistAllocation Int
    -- | Unignore the allocation
    | WhitelistAllocation Int
    -- | For a request #N in local list send confirmation to a Notary.
    -- 1. #N in user list;
    -- 2. @Just (pathToHot, partyAddr)@ : if we want to sign as a 'TrustParty';
    -- 3. Master public key;
    -- 4. Signature of slave key with master key.
    | ConfirmAllocation Int
                        (Maybe String)
                        (Maybe Text)
                        (Maybe Text)
    -- | Add a local address to storage (filepaths to sk and pk, then
    -- blockchain heights to query -- minimum and maximum)
    | ImportAddress (Maybe FilePath) FilePath Int
    | ExportAddress Int FilePath
    | DeleteAddress Int Bool
    | Dump DumpCommand
#if GtkGui
    -- | Start graphical user interface
    | StartGUI
#endif
    deriving (Show)

data DumpCommand
    = DumpHBlocks PeriodId PeriodId
    | DumpHBlock PeriodId
    | DumpMintettes
    | DumpAddresses
    | DumpPeriod
    | DumpLogs MintetteId Int Int
    | DumpMintetteUtxo MintetteId
    | DumpMintetteBlocks MintetteId PeriodId
    | DumpMintetteLogs MintetteId PeriodId
    | DumpAddress Word
    deriving (Show)

-- | Datatype describing user command line options
data UserOptions = UserOptions
    { userCommand    :: UserCommand  -- ^ Command for the program to process
    , isBankMode     :: Bool         -- ^ If creating wallet in bank-mode,
    , bankModePath   :: FilePath     -- ^ Path to bank's secret key
    , addressesNum   :: Int          -- ^ Number of addresses to create initially
#if GtkGui
    , guidbPath      :: FilePath     -- ^ Path to the gui database.
#endif
    , walletPath     :: FilePath     -- ^ Path to the wallet
    , logSeverity    :: Severity     -- ^ Logging severity
    , configPath     :: FilePath     -- ^ Configuration file path
    , defaultContext :: Bool         -- ^ Use defaultNodeContext
    } deriving (Show)

userCommandParser :: Parser UserCommand
userCommandParser =
    subparser
        (command
             "list"
             (info
                  (pure ListAddresses)
                  (progDesc
                       ("List all available addresses from wallet " <>
                        "and information about them."))) <>
#if GtkGui
         command
             "start-gui"
             (info (pure StartGUI) (progDesc "Start graphical user interface.")) <>
#endif
         command
             "update"
             (info
                  (pure UpdateBlockchain)
                  (progDesc "Query bank to sync local state with blockchain.")) <>
         command
             "send"
             (info formTransactionOpts (progDesc "Form and send transaction.")) <>
         command
             "create-multisig"
             (info
                  createMultisigOpts
                  (progDesc "Create multisignature address allocation")) <>
         command
             "list-alloc"
             (info
                  (listAllocOpts ListAllocations)
                  (progDesc
                       "List all multisignature address allocations you need to confirm")) <>
         command "list-alloc-blacklisted"
             (info
                  (listAllocOpts ListAllocationsBlacklist)
                  (progDesc $
                       "List all multisignature address allocations that " <>
                       "are blacklisted (ignored).")) <>
         command
             "alloc-confirm"
             (info
                  confirmOpts
                  (progDesc
                       "Confirm MS address allocation from `rscoin-user list-alloc`")) <>
         command "alloc-blacklist"
             (info blacklistAllocationOpts (progDesc "Blacklist an allocation")) <>
         command "alloc-whitelist"
             (info whitelistAllocationOpts
                  (progDesc "Restore an allocation from the blacklist")) <>
         command
             "import-address"
             (info
                  importAddressOpts
                  (progDesc
                       "Import address to storage given a (secretKey,publicKey) pair")) <>
         command
             "export-address"
             (info
                  exportAddressOpts
                  (progDesc "Export address' keypair  to the file.")) <>
         command
             "delete-address"
             (info
                  deleteAddressOpts
                  (progDesc $
                   "Delete all information about address from " <>
                   "the wallet (can't be returned back if not exported before).")) <>
         command
             "dump-blocks"
             (info
                  (fmap Dump $
                   DumpHBlocks <$>
                   argument
                       auto
                       (metavar "FROM" <> help "Dump from which block") <*>
                   argument auto (metavar "TO" <> help "Dump to which block"))
                  (progDesc "Dump Bank high level blocks.")) <>
         command
             "dump-block"
             (info
                  (fmap Dump $
                   DumpHBlock <$>
                   argument
                       auto
                       (metavar "ID" <>
                        help "Dump block with specific periodId"))
                  (progDesc "Dump Bank high level block.")) <>
         command
             "dump-addresses"
             (info
                  (pure $ Dump DumpAddresses)
                  (progDesc "Dump list of addresses.")) <>
         command
             "dump-mintettes"
             (info
                  (pure $ Dump DumpMintettes)
                  (progDesc "Dump list of mintettes.")) <>
         command
             "dump-period"
             (info (pure $ Dump DumpPeriod) (progDesc "Dump last period.")) <>
         command
             "dump-logs"
             (info
                  (fmap Dump $
                   DumpLogs <$>
                   argument
                       auto
                       (metavar "MINTETTE_ID" <>
                        help "Dump logs of mintette with this id.") <*>
                   argument
                       auto
                       (metavar "FROM" <> help "Dump from which entry.") <*>
                   argument auto (metavar "TO" <> help "Dump to which entry."))
                  (progDesc
                       "Dump action logs of corresponding mintette, range or entries.")) <>
         command
             "dump-mintette-utxo"
             (info
                  (fmap Dump $
                   DumpMintetteUtxo <$>
                   argument
                       auto
                       (metavar "MINTETTE_ID" <>
                        help "Dump utxo of mintette with this id."))
                  (progDesc "Dump utxo of corresponding mintette.")) <>
         command
             "dump-mintette-blocks"
             (info
                  (fmap Dump . DumpMintetteBlocks <$>
                   argument
                       auto
                       (metavar "MINTETTE_ID" <>
                        help "Dump blocks of mintette with this id.") <*>
                   argument
                       auto
                       (metavar "PERIOD_ID" <>
                        help "Dump blocks with this period id."))
                  (progDesc
                       "Dump blocks of corresponding mintette and periodId.")) <>
         command
             "dump-mintette-logs"
             (info
                  (fmap Dump . DumpMintetteLogs <$>
                   argument
                       auto
                       (metavar "MINTETTE_ID" <>
                        help "Dump logs of mintette with this id.") <*>
                   argument
                       auto
                       (metavar "PERIOD_ID" <>
                        help "Dump logs with this period id."))
                  (progDesc "Dump logs of corresponding mintette and periodId.")) <>
         command
             "dump-address"
             (info
                  (fmap Dump $
                   DumpAddress <$>
                   argument
                       auto
                       (metavar "INDEX" <> help "Index of address to dump"))
                  (progDesc "Dump address with given index.")))
  where
    formTransactionOpts =
        FormTransaction <$>
        some
            (option
                 auto
                 (long "from" <>
                  help
                      ("Tuples (a,b,c) where " <>
                       "'a' is id of address as numbered in list-wallets output, " <>
                       "'b' is integer -- amount of coins to send, " <>
                       "'c' is the color (0 for uncolored), any uncolored ~ colored.") <>
                  metavar "(INT,INT,INT)")) <*>
        strOption (long "toaddr" <> help "Address to send coins to.") <*>
        many
            (option
                 auto
                 (long "tocoin" <>
                  help
                      ("Pairs (a,b) where " <>
                       "'a' is amount of coins to send, " <>
                       "'b' is the color of that coin") <>
                  metavar "(INT,INT)"))
        -- FIXME: should we do caching here or not?
        <*>
        pure Nothing
    createMultisigOpts =
        CreateMultisigAddress <$>
        option auto (short 'm' <> metavar "INT" <> help "Number m from m/n") <*>
        many
            (strOption $
             long "uaddr" <> metavar "ADDRESS" <>
             help "User party Addresses that would own this MS address") <*>
        many
            (strOption $
             long "taddr" <> metavar "ADDRESS" <>
             help "Trust party Addresses that would own this MS address") <*>
        optional
            (strOption $
             long "master-pk" <> metavar "ADDRESS" <>
             help "Public key of master for party") <*>
        optional
            (strOption $
             long "slave-sig" <> metavar "SIGNATURE" <>
             help "Signature of slave with master public key")
    listAllocOpts allocCtor =
        allocCtor <$>
        optional
            (strOption $
             long "trust-party" <> metavar "PUBLIC KEY" <>
             help "Trust address as party")
    confirmOpts =
        ConfirmAllocation <$>
        option
            auto
            (short 'i' <> long "index" <> metavar "INT" <>
             help "Index starting from 1 in `list-alloc`") <*>
        optional
            (strOption $
             long "hot-trust" <> metavar "(SKPATH, ADDRESS)" <>
             help
                 "Pair of hot sk path and party pk if we want to confirm as Trust)") <*>
        optional
            (strOption $
             long "master-pk" <> metavar "ADDRESS" <>
             help "Public key of master for party") <*>
        optional
            (strOption $
             long "slave-sig" <> metavar "SIGNATURE" <>
             help "Signature of slave with master public key")
    importAddressOpts =
        ImportAddress <$>
        (optional $
         strOption $
         long "sk" <> help "Path to file with binary-encoded secret key" <>
         metavar "FILEPATH") <*>
        (strOption $
         long "pk" <> help "Path to file with base64-encoded public key" <>
         metavar "FILEPATH") <*>
        (option auto $
         long "query-from" <> help "Height to query blockchain from" <> value 0 <>
         metavar "INT")
    exportAddressOpts =
        ExportAddress <$>
        option
            auto
            (short 'i' <> long "index" <> help "Id of address in `list` command output." <>
             metavar "INT") <*>
        strOption
            (long "path" <> help "Path to export address' keys to." <>
             metavar "FILEPATH")
    deleteAddressOpts =
        DeleteAddress <$>
        option
            auto
            (short 'i' <> long "index" <> help "Id of address in `list` command output." <>
             metavar "INT") <*>
        switch
        (long "force" <> short 'f' <>
         help "Don't ask confirmation for deletion")
    blacklistAllocationOpts = BlacklistAllocation <$> option
        auto (short 'i' <> long "index" <> metavar "INT" <>
             help "Index of allocation, starting from 1 in `list-alloc`")
    whitelistAllocationOpts = WhitelistAllocation <$> option
        auto (short 'i' <> long "index" <> metavar "INT" <>
             help "Index of allocation, starting from 1 in `list-alloc`")

userOptionsParser :: FilePath -> FilePath -> FilePath -> Parser UserOptions
userOptionsParser dskp configDir defaultConfigPath =
    UserOptions <$> userCommandParser <*>
    switch
        (long "bank-mode" <>
         help
             ("Start the client in bank-mode. " <>
              "Is needed only on wallet initialization. " <>
              "Will load bank's secret key.")) <*>
    strOption
        (long "bank-sk-path" <> help "Path to bank's secret key." <> value dskp <>
         showDefault <>
         metavar "FILEPATH") <*>
    option
        auto
        (long "addresses-num" <>
         help
             ("The number of addresses to create " <>
              "initially with the wallet") <>
         value defaultAccountsNumber <>
         showDefault <>
         metavar "INT") <*>
    strOption
        (long "wallet-path" <> help "Path to wallet database." <>
         value (configDir </> "wallet-db") <>
         showDefault <>
         metavar "FILEPATH") <*>
#if GtkGui
    strOption
        (long "guidb-path" <> help "Path to gui database" <>
         value "gui-db" <>
         showDefault <>
         metavar "FILEPATH") <*>
#endif
    option auto
        (long "log-severity" <> value Info <> showDefault <>
         help "Logging severity" <>
         metavar "SEVERITY") <*>
    strOption
        (long "config-path" <> help "Path to configuration file" <>
         value defaultConfigPath <>
         showDefault <>
         metavar "FILEPATH") <*>
    switch (mconcat [short 'd',
                     long "default-context",
                     help ("Use default NodeContext. "
                           <> "Intended to be used for local deployment")
                    ])

-- | IO call that retrieves command line options
getUserOptions :: IO UserOptions
getUserOptions = do
    defaultSKPath <- defaultSecretKeyPath
    configDir <- configDirectory
    defaultConfigPath <- defaultConfigurationPath
    execParser $
        info
            (helper <*>
             userOptionsParser defaultSKPath configDir defaultConfigPath)
            (fullDesc <> progDesc "RSCoin user client")
