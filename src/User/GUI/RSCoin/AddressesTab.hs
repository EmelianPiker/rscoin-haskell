{-# LANGUAGE NoOverloadedStrings #-}

module GUI.RSCoin.AddressesTab
    ( createAddressesTab
    , initAddressesTab
    , updateAddressTab
    ) where

import           Control.Lens          ((^.))
import           Control.Monad         (forM_, void)
import           Data.Acid             (query)

import           Graphics.UI.Gtk       (AttrOp ((:=)))
import qualified Graphics.UI.Gtk       as G

import           GUI.RSCoin.Addresses  (VerboseAddress (..), getAddresses)
import           GUI.RSCoin.Glade      (GladeMainWindow (..))
import           GUI.RSCoin.MainWindow (AddressesTab (..), MainWindow (..))
import qualified RSCoin.Core           as C
import           RSCoin.User           (RSCoinUserState)
import           RSCoin.User.AcidState (GetAllAddresses (..))
import           RSCoin.User.Wallet    (publicAddress)

createAddressesTab :: GladeMainWindow -> IO AddressesTab
createAddressesTab GladeMainWindow{..} =
    AddressesTab gTreeViewAddressesView <$> G.listStoreNew []

initAddressesTab :: RSCoinUserState -> MainWindow -> IO ()
initAddressesTab st mw@MainWindow{..} = do
    let AddressesTab{..} = tabAddresses
    G.treeViewSetModel treeViewAddressesView addressesModel
    addressesCol <- G.treeViewColumnNew
    balanceCol <- G.treeViewColumnNew
    G.treeViewColumnSetTitle addressesCol "Address"
    G.treeViewColumnSetTitle balanceCol "Balance"
    renderer <- G.cellRendererTextNew
    G.cellLayoutPackStart addressesCol renderer False
    G.cellLayoutPackStart balanceCol renderer False
    G.cellLayoutSetAttributes addressesCol renderer addressesModel $ \a ->
        [G.cellText := C.printPublicKey (address a)]
    G.cellLayoutSetAttributes balanceCol renderer addressesModel $ \a ->
        [G.cellText := show (balance a)]
    void $ G.treeViewAppendColumn treeViewAddressesView addressesCol
    void $ G.treeViewAppendColumn treeViewAddressesView balanceCol
    updateAddressTab st mw

updateAddressTab :: RSCoinUserState -> MainWindow -> IO ()
updateAddressTab st MainWindow{..} = do
    let AddressesTab{..} = tabAddresses
    G.listStoreClear addressesModel
    a <- getAddresses st
    forM_ a $ G.listStoreAppend addressesModel
