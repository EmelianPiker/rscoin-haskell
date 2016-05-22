{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE NoOverloadedStrings #-}

-- | This module describes main GUI bindings
module GUI.RSCoin.GUI (startGUI, red, green) where

import           Control.Monad          (void)
import           Control.Monad.IO.Class (liftIO)

import           Data.Maybe             (fromJust)
import qualified Data.Text              as T

import           Graphics.UI.Gtk        (AttrOp ((:=)), on)
import qualified Graphics.UI.Gtk        as G

import           GUI.RSCoin.Glade       (GladeMainWindow (..), importGlade)

import           Paths_rscoin           (getDataFileName)

import           System.FilePath        (takeBaseName)

data ModelNode = ModelNode
    { mIsSend      :: Bool
    , mIsConfirmed :: Bool
    , mTime        :: String
    , mAddress     :: String
    , mAmount      :: Integer
    }

type Model = G.ListStore ModelNode

green, red:: G.Color
green = G.Color 0 65535 0
red = G.Color 51199 8960 8960

createRandomModel :: G.TreeView -> IO Model
createRandomModel view = do
    model <- G.listStoreNew []
    appendColumn model True "Status" statusSetter
    appendColumn model True "Confirmation" confirmationSetter
    appendColumn model True "Time" timeSetter
    appendColumn model True "Address" addrSetter
    appendColumn model True "Amount" amountSetter
    G.treeViewSetModel view model
    return model
  where
    appendColumn model expand title attributesSetter = do
        column <- G.treeViewColumnNew
        G.treeViewColumnSetTitle column title
        G.treeViewColumnSetExpand column expand
        renderer <- G.cellRendererTextNew
        G.cellLayoutPackStart column renderer False
        G.cellLayoutSetAttributes column renderer model attributesSetter
        void $ G.treeViewAppendColumn view column
    statusSetter ModelNode{..} =
        [ G.cellText :=
          if mIsSend
              then "Out"
              else "In"]
    confirmationSetter ModelNode{..} =
        [ G.cellText :=
          if mIsConfirmed
              then "Confirmed"
              else "Unconfirmed"]
    timeSetter ModelNode{..} = [G.cellText := mTime]
    addrSetter ModelNode{..} = [G.cellText := mAddress]
    amountSetter ModelNode{..} = [G.cellText := showSigned mAmount]
    showSigned a
      | a > 0 = "+" ++ show a
      | otherwise = show a

addRandomData :: Model -> IO ()
addRandomData model = mapM_ (G.listStoreAppend model) randomModelData
  where
    randomModelData = do
        tm <- ["2:20", "6:42", "12:31"]
        st2 <- [True, False]
        am <- [123, -3456, 12345, -45323]
        st1 <- [True, False]
        addr <- [ "A7FUZi67YbBonrD9TrfhX7wnnFxrIRflbMFOpI+r9dOc"
                , "G7FuzI67zbBbnrD9trfh27anNf2RiRFLBmfBPi+R9DBC"
                ]
        return $ ModelNode st1 st2 tm addr am

-- ICONS --
loadIcons :: IO ()
loadIcons = mapM_ loadIcon iconList
  where
    iconList = [ "resources/icons/wallet.png"
               , "resources/icons/people.png"
               , "resources/icons/send.png"
               , "resources/icons/options.png"
               ]
    loadIcon path = do
        icon <- G.iconSourceNew
        getDataFileName path >>= G.iconSourceSetFilename icon
        icons <- G.iconSetNew
        G.iconSetAddSource icons icon
        iconf <- G.iconFactoryNew
        G.iconFactoryAdd iconf (T.toLower . T.pack $ takeBaseName path) icons
        G.iconFactoryAddDefault iconf

notebookGetAllPages :: G.NotebookClass self => self -> IO [G.Widget]
notebookGetAllPages nb = do
    npages <- G.notebookGetNPages nb
    mapM (fmap fromJust . G.notebookGetNthPage nb) [0..npages - 1]

notebookGetAllTabLabelText
    :: G.NotebookClass self
    => self
    -> IO [Maybe T.Text]
notebookGetAllTabLabelText nb = notebookGetAllPages nb >>= mapM (G.notebookGetTabLabelText nb)

notebookRemoveAllPages
    :: G.NotebookClass self
    => self
    -> IO ()
notebookRemoveAllPages nb = do
    npages <- G.notebookGetNPages nb
    sequence_ . replicate npages $ G.notebookRemovePage nb 0

setNotebookIcons :: G.NotebookClass self => self -> G.IconSize -> IO ()
setNotebookIcons nb size = do
    pages <- zip <$> notebookGetAllPages nb <*> notebookGetAllTabLabelText nb
    notebookRemoveAllPages nb
    sequence_ $ map (addIconPage nb) pages
  where
    addIconPage nb (widget, Nothing) = do
        noIcon <- G.labelNew $ Just "no label"
        G.notebookAppendPageMenu nb widget noIcon noIcon
    addIconPage nb (widget, Just name) = do
        image <- G.imageNewFromStock (T.toLower name) size
        G.notebookAppendPageMenu nb widget image image

-- ICONS --

startGUI :: IO ()
startGUI = do
    void G.initGUI
    GladeMainWindow {..} <- importGlade
    model <- createRandomModel treeViewWallet
    addRandomData model
    loadIcons
    setNotebookIcons notebookMain G.IconSizeSmallToolbar
    sendAmountAdjustment <- G.adjustmentNew 0 0 1000000000 1 1 1
    G.spinButtonSetAdjustment spinButtonSendAmount sendAmountAdjustment
    void (window `on` G.deleteEvent $ liftIO G.mainQuit >> return False)
    G.widgetShowAll window
    G.mainGUI
