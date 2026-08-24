-----------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
-----------------------------------------------------------------------------
-- | Bundled images. rspeedy never sees the @src@ strings the GHC JS backend
-- emits, and the Lynx \<image\> element doesn't resolve a relative @src@
-- against the bundle URL, so @nix/mk-lynx-bundle.nix@ @import@s every file
-- under @assets/@ with @?inline@ (rspeedy embeds it as a @data:@ URI /in the
-- bundle/ — offline, no asset server) and registers them by relative name on
-- @globalThis.__misoGramAssets@. 'asset' reads that registry back.
module MisoGram.Assets
  ( asset
  , photo
  , icon
  ) where
-----------------------------------------------------------------------------
import           Miso.DSL (jsg, (!), fromJSValUnchecked)
import           Miso.String (MisoString)
import           System.IO.Unsafe (unsafePerformIO)
-----------------------------------------------------------------------------
-- | Resolve a bundled asset by its path under @assets/@ (e.g.
-- @"photos/p03.jpg"@, @"icons/heart.png"@) to its embedded @data:@ URI.
--
-- The registry is populated once at bundle load and never mutates, so the
-- read is referentially transparent.
asset :: MisoString -> MisoString
asset name = unsafePerformIO (jsg "__misoGramAssets" >>= (! name) >>= fromJSValUnchecked)
{-# NOINLINE asset #-}
-----------------------------------------------------------------------------
-- | A ramen photo, by its @photos/@ file name (e.g. @"p03.jpg"@).
photo :: MisoString -> MisoString
photo name = asset ("photos/" <> name)
-----------------------------------------------------------------------------
-- | A line icon from @assets/icons/@, by name without extension (e.g.
-- @"heart"@, @"heart-red"@, @"home-fill-white"@).
icon :: MisoString -> MisoString
icon name = asset ("icons/" <> name <> ".png")
-----------------------------------------------------------------------------
