-----------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
-----------------------------------------------------------------------------
-- | The main-thread swiper behind every horizontally (or vertically) paged
-- surface in the app: the feed's photo carousels, the full-screen viewer, and
-- the reels pager.
--
-- It is the miso-lynx-gallery @product-detail@ swiper (itself a port of
-- @lynx-examples/examples/swiper@), generalised to __many tracks__ and
-- __either axis__. All touch handling runs on the Lynx main thread (MTS): a
-- @touchstart@ anchors the drag, @touchmove@ only records where the finger
-- wants the track, a vsync-coalesced 'eachFrame' loop paints the latest offset
-- once per frame, and @touchend@ hands the settle to a native compositor
-- transition. The only thing that crosses to the background thread is the page
-- the track settled on ('swipeEnd' returns it; @update@ forwards it with
-- 'Miso.Effect.runOnBG').
--
-- A track describes itself through attributes, read on the MTS with
-- 'getAttribute' when the finger lands, so one global 'MainThreadRef' serves
-- every carousel on screen:
--
-- * @id@ — the key its offset is remembered under between drags
-- * @data-n@ — page count
-- * @data-axis@ — @x@ (default) or @y@
-- * @data-size@ — page size in px for a vertical track (horizontal tracks are
--   one screen wide, see 'screenWidthPx')
-- * @data-start@ — the page to open on (the viewer opens on the tapped photo)
--
-- Remembered offsets are per element instance: 'resetSwipers' must run when
-- navigation recreates the tracks (fresh elements sit at page 0 again).
module MisoGram.Swiper
  ( swipeStart
  , swipeMove
  , swipeEnd
  , swipeInit
  , resetSwipers
  , touchPos
  , screenWidthPx
  ) where
-----------------------------------------------------------------------------
import           Control.Monad (when, unless)
import           Data.Maybe (fromMaybe)
import qualified Miso.CSS as CSS
import           Miso (DOMRef)
import           Miso.Native.MainThread
  ( setStyleProperty, setStyleProperties, setStylePropertyTransform, eachFrame
  , getAttribute, getSystemInfo, SystemInfo (pixelWidth, pixelRatio)
  , MainThreadRef, mainThreadRef, readMainThreadRef, writeMainThreadRef
  , modifyMainThreadRef )
import qualified Miso.Native.Element.View.Event as VE
import           Miso.String (MisoString, fromMisoString)
import           System.IO.Unsafe (unsafePerformIO)
import           Text.Read (readMaybe)
-----------------------------------------------------------------------------
-- | The swiper's main-thread scratch — the sample's @useMainThreadRef@s —
-- touched only inside MTS handlers / rAF callbacks, so it never races the
-- background thread.
data Swipe = Swipe
  { sStartPos    :: !Double     -- ^ finger position (along the axis) at @touchstart@
  , sStartOffset :: !Double     -- ^ committed offset the drag began from
  , sCurOffset   :: !Double     -- ^ committed track offset (0 at page 0, negative onward)
  , sWantOffset  :: !Double     -- ^ latest offset the finger wants (written by @touchmove@)
  , sApplied     :: !Double     -- ^ offset the follow loop last painted (skip idle frames)
  , sVelocity    :: !Double     -- ^ smoothed finger velocity, px/ms (negative = forward)
  , sLastTs      :: !Double     -- ^ frame timestamp of the last velocity sample
  , sLastWant    :: !Double     -- ^ 'sWantOffset' at the last velocity sample
  , sActive      :: !Bool       -- ^ finger currently down?
  , sKey         :: !MisoString -- ^ @id@ of the track being dragged
  , sCount       :: !Int        -- ^ its page count
  , sSize        :: !Double     -- ^ its page size (px)
  , sVertical    :: !Bool       -- ^ dragging along y?
  , sOffsets     :: [(MisoString, Double)]  -- ^ settled offset of every track touched so far
  }
-----------------------------------------------------------------------------
swipe :: MainThreadRef Swipe
swipe = mainThreadRef (Swipe 0 0 0 0 0 0 0 0 False "" 1 0 False [])
{-# NOINLINE swipe #-}
-----------------------------------------------------------------------------
-- | One horizontal page's width in px — the sample's @SystemInfo.pixelWidth /
-- SystemInfo.pixelRatio@, read from @lynx.SystemInfo@ (MTS-only; 0 elsewhere,
-- and every caller guards on it, so a missing global yields an inert swiper
-- rather than a throw).
screenWidthPx :: Double
screenWidthPx = unsafePerformIO $ do
  msi <- getSystemInfo
  pure $ case msi of
    Just si | pixelRatio si > 0 -> pixelWidth si / pixelRatio si
    _                           -> 0
{-# NOINLINE screenWidthPx #-}
-----------------------------------------------------------------------------
-- | The finger's window position (the sample's @e.touches[0].clientX@).
touchPos :: VE.TouchEvent -> (Double, Double)
touchPos = VE.client
-----------------------------------------------------------------------------
-- | What a track says about itself (see the module header).
data Geo = Geo
  { gKey      :: MisoString
  , gCount    :: Int
  , gSize     :: Double
  , gVertical :: Bool
  , gStart    :: Int
  }
-----------------------------------------------------------------------------
readGeo :: DOMRef -> IO Geo
readGeo ref = do
  key   <- getAttribute ref "id"
  n     <- num <$> getAttribute ref "data-n"
  axis  <- getAttribute ref "data-axis"
  size  <- num <$> getAttribute ref "data-size"
  start <- num <$> getAttribute ref "data-start"
  let vertical = axis == "y"
  pure Geo
    { gKey      = key
    , gCount    = max 1 (round n)
    , gSize     = if vertical then size else screenWidthPx
    , gVertical = vertical
    , gStart    = round start
    }
  where
    num :: MisoString -> Double
    num s = fromMaybe 0 (readMaybe (fromMisoString s))
-----------------------------------------------------------------------------
-- Track geometry, in terms of one page size. Only evaluated once the size is
-- > 0 (every caller guards), so the divisions are safe.
-----------------------------------------------------------------------------
-- | The track offset (px) that shows page @i@ (0, -size, -2·size, …).
pageOffset :: Double -> Int -> Double
pageOffset size i = negate (fromIntegral i * size)

-- | The page nearest a given track offset.
pageAt :: Double -> Double -> Int
pageAt size off = round (negate off / size)

-- | Clamp an offset so the deck can't be pulled past either end.
clampOffset :: Double -> Int -> Double -> Double
clampOffset size n = max (pageOffset size (n - 1)) . min 0

-- | Clamp a page index to the deck.
clampPage :: Int -> Int -> Int
clampPage n = max 0 . min (n - 1)
-----------------------------------------------------------------------------
-- | The settled offset of a track: what it was last left at, or its
-- @data-start@ page for a fresh element.
storedOffset :: Swipe -> Geo -> Double
storedOffset s g = fromMaybe (pageOffset (gSize g) (gStart g)) (lookup (gKey g) (sOffsets s))
-----------------------------------------------------------------------------
-- | @handleTouchStart@: interrupt any in-flight snap (kill the transition so
-- the track follows the finger 1:1), anchor the drag, start the vsync follow
-- loop.
swipeStart :: (Double, Double) -> DOMRef -> IO ()
swipeStart (x, y) ref = do
  g <- readGeo ref
  s <- readMainThreadRef swipe
  when (gSize g > 0) $ do
    let pos = if gVertical g then y else x
        off = storedOffset s g
    setStyleProperty ref "transition" "none"
    writeMainThreadRef swipe s
      { sStartPos = pos, sStartOffset = off, sCurOffset = off
      , sWantOffset = off, sApplied = off, sLastWant = off
      , sVelocity = 0, sLastTs = 0, sActive = True
      , sKey = gKey g, sCount = gCount g, sSize = gSize g, sVertical = gVertical g
      }
    unless (sActive s) (followLoop ref)
-----------------------------------------------------------------------------
-- | @handleTouchMove@: just record where the finger wants the track. The
-- follow loop applies it once per frame — cheap here, so bursty touchmoves
-- don't jank.
swipeMove :: (Double, Double) -> IO ()
swipeMove (x, y) = modifyMainThreadRef swipe $ \s ->
  let pos = if sVertical s then y else x
  in if sActive s then s { sWantOffset = sStartOffset s + (pos - sStartPos s) } else s
-----------------------------------------------------------------------------
-- | @handleTouchEnd@: pick the target page (distance OR a flick), hand the
-- settle to a native CSS transition, remember where this track ended up, and
-- report the page it settled on (for the background thread to record).
swipeEnd :: DOMRef -> IO (Maybe (MisoString, Int))
swipeEnd ref = do
  s <- readMainThreadRef swipe
  if not (sActive s) || sSize s <= 0
    then pure Nothing
    else do
      let to  = snapTarget s
          idx = pageAt (sSize s) to
      writeMainThreadRef swipe s
        { sActive = False, sCurOffset = to
        , sOffsets = (sKey s, to) : filter ((/= sKey s) . fst) (sOffsets s)
        }
      paintSnap (sVertical s) ref to
      pure (Just (sKey s, idx))
-----------------------------------------------------------------------------
-- | A track just laid out (@layoutchange@): if it should open on a page other
-- than 0 and hasn't been touched yet, jump there instantly.
swipeInit :: DOMRef -> IO ()
swipeInit ref = do
  g <- readGeo ref
  s <- readMainThreadRef swipe
  when (gSize g > 0 && gStart g > 0 && lookup (gKey g) (sOffsets s) == Nothing) $ do
    let off = pageOffset (gSize g) (clampPage (gCount g) (gStart g))
    setStyleProperty ref "transition" "none"
    setStylePropertyTransform ref [ axisTranslate (gVertical g) off ]
    writeMainThreadRef swipe s { sOffsets = (gKey g, off) : sOffsets s }
-----------------------------------------------------------------------------
-- | Forget every remembered offset (and any half-finished drag). Run whenever
-- navigation recreates the tracks.
resetSwipers :: IO ()
resetSwipers = modifyMainThreadRef swipe $ \s -> s { sOffsets = [], sActive = False }
-----------------------------------------------------------------------------
axisTranslate :: Bool -> Double -> CSS.TransformFn
axisTranslate vertical off =
  (if vertical then CSS.translateY else CSS.translateX) (CSS.px (round off :: Int))
-----------------------------------------------------------------------------
-- | Paint the track at @off@ (clamped) with no transition — the drag follow
-- path, run once per animation frame during a drag.
paintOffset :: Bool -> DOMRef -> Double -> IO ()
paintOffset vertical ref off = setStylePropertyTransform ref [ axisTranslate vertical off ]
-----------------------------------------------------------------------------
-- | Settle to @to@ via a native compositor transition (ease-out) — the snap
-- runs off the JS thread, so there are no per-frame flushes during it.
-- 'CSS.transition_' emits the single @transition@ shorthand key, the same one
-- 'swipeStart' clears with @transition: none@.
paintSnap :: Bool -> DOMRef -> Double -> IO ()
paintSnap vertical ref to = setStyleProperties ref
  [ CSS.transition_ "transform" (CSS.s 0.3) (CSS.cubicBezier 0.22 1 0.36 1)
  , CSS.transforms [ axisTranslate vertical to ]
  ]
-----------------------------------------------------------------------------
-- | Where the swiper should settle after a drag. A page flips when the finger
-- either travelled past a fraction of a page (distance) __or__ was moving fast
-- enough when it lifted (a flick) — so a quick short swipe still advances. One
-- page per gesture, else spring back.
snapTarget :: Swipe -> Double
snapTarget s = pageOffset size (clampPage (sCount s) (pageAt size (sStartOffset s) + step))
  where
    size = sSize s
    frac = negate (sCurOffset s - sStartOffset s) / size   -- fraction of a page dragged forward
    vel  = sVelocity s
    step | vel < negate velThresh =  1   -- a flick wins over distance…
         | vel >  velThresh       = -1
         | frac >  distThresh     =  1   -- …else fall back to how far it was dragged
         | frac < -distThresh     = -1
         | otherwise              =  0
    distThresh = 0.2      -- ~20% of a page commits the flip
    velThresh  = 0.3      -- px/ms (~300 px/s) counts as a flick
-----------------------------------------------------------------------------
-- | Fold this frame's finger motion into a smoothed velocity (px/ms). Skipped
-- on the first sample (no prior timestamp) and when no time has elapsed.
sampleVelocity :: Double -> Swipe -> Swipe
sampleVelocity ts s = s { sVelocity = v, sLastTs = ts, sLastWant = sWantOffset s }
  where
    dt = ts - sLastTs s
    v | sLastTs s > 0 && dt > 0 = 0.6 * sVelocity s + 0.4 * ((sWantOffset s - sLastWant s) / dt)
      | otherwise               = sVelocity s
-----------------------------------------------------------------------------
-- | The vsync-coalesced drag follow loop. Each animation frame it samples the
-- finger velocity (for flick detection) and, if the finger moved, paints the
-- latest 'sWantOffset' — coalescing the device's bursty @touchmove@ stream to
-- one flush per frame. Stops when 'sActive' clears (on touchend).
followLoop :: DOMRef -> IO ()
followLoop ref = eachFrame $ \ts -> do
  s <- readMainThreadRef swipe
  if not (sActive s)
    then pure False
    else do
      modifyMainThreadRef swipe (sampleVelocity ts)
      when (sWantOffset s /= sApplied s) $ do
        let real = clampOffset (sSize s) (sCount s) (sWantOffset s)
        paintOffset (sVertical s) ref real
        modifyMainThreadRef swipe $ \s' -> s' { sApplied = sWantOffset s, sCurOffset = real }
      pure True
-----------------------------------------------------------------------------
