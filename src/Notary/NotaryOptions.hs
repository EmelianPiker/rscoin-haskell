-- | Command line options for Notary.

module NotaryOptions
        ( Options (..)
        , getOptions
        ) where

import           Data.Text              (Text)
import           Options.Applicative    (Parser, auto, execParser, fullDesc,
                                         help, helper, info, long, many,
                                         metavar, option, progDesc,
                                         short, showDefault, switch, value,
                                         (<>))
import           System.FilePath        ((</>))

import           Serokell.Util.OptParse (strOption)

import           RSCoin.Core            (PeriodId, Severity (Error),
                                         configDirectory,
                                         defaultConfigurationPath,
                                         notaryAliveSizeDefault)

data Options = Options
    { cliPath           :: FilePath
    , cliLogSeverity    :: Severity
    , cliMemMode        :: Bool
    , cliWebPort        :: Int
    , cliConfigPath     :: FilePath
    , cliTrustedKeys    :: [Text]
    , cliAliveSize      :: PeriodId
    , cloDefaultContext :: Bool
    } deriving Show

optionsParser :: FilePath -> FilePath -> Parser Options
optionsParser configDir defaultConfigPath =
    Options <$>
    strOption
        (long "path" <> value (configDir </> "notary-db") <> showDefault <>
         help "Path to Notary database" <>
         metavar "FILEPATH") <*>
    option
        auto
        (long "log-severity" <> value Error <> showDefault <>
         help "Logging severity" <>
         metavar "SEVERITY") <*>
    switch (short 'm' <> long "memory-mode" <> help "Run in memory mode") <*>
    option
        auto
        (long "web-port" <> value 8090 <> showDefault <> help "Web port" <>
         metavar "PORT") <*>
    strOption
        (long "config-path" <> help "Path to configuration file" <>
         value defaultConfigPath <>
         showDefault <>
         metavar "FILEPATH") <*>
    many
        (strOption $
         long "trust-keys" <> metavar "PUBLIC KEY" <>
         help
             "Public keys notary will trust as master keys. If not specifed \
               \then notary will trust any key") <*>
    option auto
        (long "alive-size" <> metavar "INT" <> value notaryAliveSizeDefault <>
         showDefault <> help "Number of periods to keep requests alive") <*>
    switch
        (mconcat
             [ short 'd'
             , long "default-context"
             , help
                   ("Use default NodeContext. " <>
                    "Intended to be used for local deployment")])

getOptions :: IO Options
getOptions = do
    configDir <- configDirectory
    defaultConfigPath <- defaultConfigurationPath
    execParser $
        info
            (helper <*> optionsParser configDir defaultConfigPath)
            (fullDesc <> progDesc "RSCoin's Notary")
