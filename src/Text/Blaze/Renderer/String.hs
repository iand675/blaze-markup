-- | A renderer that produces a native Haskell 'String', mostly meant for
-- debugging purposes.
--
{-# LANGUAGE OverloadedStrings, Rank2Types #-}
module Text.Blaze.Renderer.String
    ( fromChoiceString
    , renderMarkup
    , renderHtml
    ) where

import Data.Functor.Identity

import Data.List (isInfixOf)

import qualified Data.ByteString.Char8 as SBC
import qualified Data.Text as T
import qualified Data.ByteString as S

import Text.Blaze.Internal

-- | Escape predefined XML entities in a string
--
escapeMarkupEntities :: String  -- ^ String to escape
                   -> String  -- ^ String to append
                   -> String  -- ^ Resulting string
escapeMarkupEntities []     k = k
escapeMarkupEntities (c:cs) k = case c of
    '<'  -> '&' : 'l' : 't' : ';'             : escapeMarkupEntities cs k
    '>'  -> '&' : 'g' : 't' : ';'             : escapeMarkupEntities cs k
    '&'  -> '&' : 'a' : 'm' : 'p' : ';'       : escapeMarkupEntities cs k
    '"'  -> '&' : 'q' : 'u' : 'o' : 't' : ';' : escapeMarkupEntities cs k
    '\'' -> '&' : '#' : '3' : '9' : ';'       : escapeMarkupEntities cs k
    x    -> x                                 : escapeMarkupEntities cs k

-- | Render a 'ChoiceString'.
--
fromChoiceString :: ChoiceString  -- ^ String to render
                 -> String        -- ^ String to append
                 -> String        -- ^ Resulting string
fromChoiceString (Static s)     = getString s
fromChoiceString (String s)     = escapeMarkupEntities s
fromChoiceString (Text s)       = escapeMarkupEntities $ T.unpack s
fromChoiceString (ByteString s) = (SBC.unpack s ++)
fromChoiceString (PreEscaped x) = case x of
    String s -> (s ++)
    Text   s -> (\k -> T.foldr (:) k s)
    s        -> fromChoiceString s
fromChoiceString (External x) = case x of
    -- Check that the sequence "</" is *not* in the external data.
    String s     -> if "</" `isInfixOf` s then id else (s ++)
    Text   s     -> if "</" `T.isInfixOf` s then id else (\k -> T.foldr (:) k s)
    ByteString s -> if "</" `S.isInfixOf` s then id else (SBC.unpack s ++)
    s            -> fromChoiceString s
fromChoiceString (AppendChoiceString x y) =
    fromChoiceString x . fromChoiceString y
fromChoiceString EmptyChoiceString = id
{-# INLINE fromChoiceString #-}

-- | Render some 'Markup' to an appending 'String'.
--
renderString :: Markup  -- ^ Markup to render
             -> String  -- ^ String to append
             -> String  -- ^ Resulting String
renderString = go id 
  where
    go :: (String -> String) -> Markup -> String -> String
    go attrs (Parent _ open close content) =
        getString open . attrs . ('>' :) . go id content . getString close
    go attrs (CustomParent tag content) =
        ('<' :) . fromChoiceString tag . attrs . ('>' :) .  go id content .
        ("</" ++) . fromChoiceString tag . ('>' :)
    go attrs (Leaf _ begin end) = getString begin . attrs . getString end
    go attrs (CustomLeaf tag close) =
        ('<' :) . fromChoiceString tag . attrs .
        (if close then (" />" ++) else ('>' :))
    go attrs (AddAttribute _ key value h) = flip go h $
        getString key . fromChoiceString value . ('"' :) . attrs
    go attrs (AddCustomAttribute key value h) = flip go h $
        (' ' :) . fromChoiceString key . ("=\"" ++) . fromChoiceString value .
        ('"' :) .  attrs
    go _ (Content content) = fromChoiceString content
    go attrs (Append h1 h2) = go attrs h1 . go attrs h2
    go _ Empty = id
    {-# NOINLINE go #-}
{-# INLINE renderString #-}

-- | Render markup to a lazy 'String'.
--
renderMarkup :: Monad m => MarkupM m a -> m String
renderMarkup (MarkupM m) = do
    (_, mr) <- m
    return $ renderString mr ""
{-# INLINE renderMarkup #-}

renderHtml :: Monad m => MarkupM m a -> m String
renderHtml = renderMarkup
{-# INLINE renderHtml #-}
{-# DEPRECATED renderHtml
    "Use renderHtml from Text.Blaze.Html.Renderer.String instead" #-}
