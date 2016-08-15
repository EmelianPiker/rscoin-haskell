module App.View.Alert where

import Prelude                     (const, ($), (==), (<<<))

import App.Types                   (State, Action (..))

import Data.Maybe                  (Maybe (..))

import Pux.Html                    (Html, div, text, span, button,
                                    strong)
import Pux.Html.Attributes         (className, aria, data_, type_,
                                    role)
import Pux.Html.Events             (onClick)

view :: State -> Html Action
view state =
    case state.error of
        Just e ->
            div
                [ className "alert alert-danger alert-dismissible"
                , role "alert"
                ]
                [ button
                    [ type_ "button"
                    , className "close"
                    , data_ "dismiss" "alert"
                    , aria "label" "Close"
                    , onClick $ const DismissError
                    ]
                    [ span
                        [ aria "hidden" "true" ]
                        [ text "×" ]
                    ]
                , strong
                    []
                    [ text "Error! " ]
                , text e
                ]
        Nothing -> div [] []
