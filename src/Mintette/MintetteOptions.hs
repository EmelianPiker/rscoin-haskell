-- | Command line options for Mintette

module MintetteOptions
       ( Command (..)
       , Options (..)
       , ServeOptions (..)
       , AddToBankOptions (..)

       , getOptions
       ) where

import           Data.Maybe             (fromMaybe)
import           Options.Applicative    (Parser, auto, command, execParser, fullDesc,
                                         help, helper, info, long, many, metavar, option,
                                         progDesc, short, showDefault, subparser, switch,
                                         value, (<>))
import           System.FilePath        ((</>))

import           Serokell.Util.OptParse (strOption)

import           RSCoin.Core            (Address (Address), Severity (Error),
                                         configDirectory, constructPublicKey,
                                         defaultConfigurationPath, defaultPort,
                                         defaultSecretKeyPath)

data Command
    = Serve ServeOptions
    | DumpStatistics
    | CreatePermissionKeypair
    | AddToBank AddToBankOptions

data ServeOptions = ServeOptions
    { cloPort            :: Int
    , cloSecretKeyPath   :: FilePath
    , cloAutoCreateKey   :: Bool
    , cloActionLogsLimit :: Word
    }

data AddToBankOptions = AddToBankOptions
    { atboMintetteHost  :: String
    , atboMintettePort  :: Int
    , atboSecretKeyPath :: FilePath
    }

data Options = Options
    { cloCommand        :: Command
    , cloPath           :: FilePath
    , cloLogSeverity    :: Severity
    , cloMemMode        :: Bool
    , cloConfigPath     :: FilePath
    , cloDefaultContext :: Bool
    , cloRebuildDB      :: Bool
    , cloPermittedAddrs :: [Address]
    }

commandParser :: FilePath -> Parser Command
commandParser defaultSKPath =
    subparser
        (command "serve" (info serveOpts (progDesc "Serve users and others")) <>
         command
             "dump-statistics"
             (info (pure DumpStatistics) (progDesc "Dump statistics")) <>
         command
             "create-permission-keypair"
             -- TODO: option to override the generated keypair location
             (info (pure CreatePermissionKeypair) (progDesc "Generates mintette permission keypair")) <>
         command
             "add-to-bank"
             (info addToBankOpts (progDesc "Adds mintette to the bank given the bank has mintette public key permitted")))
  where
    addToBankOpts =
      fmap AddToBank $
      AddToBankOptions
      <$> strOption (short 'h' <> long "host" <> metavar "HOST")
      <*> option auto (short 'p' <> long "port" <> metavar "INTEGER")
      <*> strOption
            (long "sk" <> value defaultSKPath <> metavar "FILEPATH" <>
             help "Path to the secret key" <>
             showDefault <>
             metavar "FILEPATH")
    serveOpts =
        fmap Serve $
        ServeOptions <$>
        option
            auto
            (short 'p' <> long "port" <> value defaultPort <>
             showDefault <> metavar "INTEGER") <*>
        strOption
            (long "sk" <> value defaultSKPath <> metavar "FILEPATH" <>
             help "Path to the secret key" <>
             showDefault <>
             metavar "FILEPATH") <*>
        switch
            (long "auto-create-sk" <>
             help
                 ("If the \"sk\" is pointing to non-existing " <>
                  "file, generate a keypair")) <*>
        option auto (long "action-logs-limit" <> value 100000 <> showDefault)

optionsParser :: FilePath -> FilePath -> FilePath -> Parser Options
optionsParser defaultSKPath configDir defaultConfigPath =
    Options <$> commandParser defaultSKPath <*>
    strOption
        (long "path" <> value (configDir </> "mintette-db") <> showDefault <>
         help "Path to database" <>
         metavar "FILEPATH") <*>
    option
        auto
        (long "log-severity" <> value Error <> showDefault <>
         help "Logging severity" <>
         metavar "SEVERITY") <*>
    switch (short 'm' <> long "memory-mode" <> help "Run in memory mode") <*>
    strOption
        (long "config-path" <> help "Path to configuration file" <>
         value defaultConfigPath <>
         showDefault <>
         metavar "FILEPATH") <*>
    switch
        (mconcat
             [ short 'd'
             , long "default-context"
             , help
                   ("Use default NodeContext. " <>
                    "Intended to be used for local deployment")]) <*>
    switch
        (mconcat
             [ short 'r'
             , long "rebuild-db"
             , help
                   "Erase database if it already exists"]) <*>
    many
        (Address .
         fromMaybe (error "failed to read permit-addr address: not base64") .
         constructPublicKey <$>
             strOption
                 (long "permit-addr" <>
                  help "Permitted address" <>
                  metavar "ADDRESS"))



getOptions :: IO Options
getOptions = do
    defaultSKPath <- defaultSecretKeyPath
    configDir <- configDirectory
    defaultConfigPath <- defaultConfigurationPath
    execParser $
        info
            (helper <*> optionsParser defaultSKPath configDir defaultConfigPath)
            (fullDesc <> progDesc "RSCoin's Mintette")
