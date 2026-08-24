-----------------------------------------------------------------------------
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE StaticPointers    #-}
-----------------------------------------------------------------------------
-- | Misogram — an Instagram clone made of ramen, on miso's native (LynxJS
-- dual-thread) backend.
--
-- One root 'Component' owns the whole app. Its 'Model' is the navigation
-- state (a current 'Screen' over a back stack, plus the selected 'Tab'), the
-- feed, and everything you can toggle or type; 'updateModel' is the app's
-- logic and runs on the background thread (BTS).
--
-- The only main-thread (MTS) work is the swiper ("MisoGram.Swiper"): its
-- touch handlers are @*MainWith@ events, so a drag never round-trips to the
-- BTS. The two threads are bridged explicitly — a settled page crosses MTS→BTS
-- as 'Snapped' → 'SetPage' via 'runOnBG', and navigation crosses BTS→MTS as
-- 'ResetSwipers' via 'runOnMain' (freshly created tracks sit at page 0 again).
module Main where
-----------------------------------------------------------------------------
import           Control.Concurrent (threadDelay)
import           Miso hiding (screen)
import           Miso.DSL (jsg, (#), syncCallback2, fromJSValUnchecked)
import           Miso.Native
import qualified Miso.String as MS
-----------------------------------------------------------------------------
import           MisoGram.Data
import           MisoGram.Swiper
import           MisoGram.Types
import           MisoGram.View (viewModel)
-----------------------------------------------------------------------------
main :: IO ()
main = native (nativeEvents <> nativeXEvents) (static (mountStatic app))
-----------------------------------------------------------------------------
app :: Component () () Model Action
app = (component initialModel updateModel viewModel) { mount = Just Boot }
-----------------------------------------------------------------------------
initialModel :: Model
initialModel = Model
  { screen       = ScreenSplash
  , stack        = []
  , tab          = Home
  , posts        = initialPosts
  , liked        = [3, 8]
  , saved        = [1]
  , following    = [0, 1, 3, 6]
  , pages        = []
  , bigHeart     = Nothing
  , lastTap      = Nothing
  , commentDraft = ""
  , searchQuery  = ""
  , picked       = Nothing
  , captionDraft = ""
  , nextPostId   = 100
  , toast        = Nothing
  , reelsHeight  = 0
  , profileTab   = 0
  , notifsSeen   = False
  , kbHeight     = 0
  }
-----------------------------------------------------------------------------
-- | How long the splash screen holds, in microseconds.
splashHold :: Int
splashHold = 1600000

-- | Two taps closer together than this (ms) are a double tap.
doubleTapMs :: Double
doubleTapMs = 350
-----------------------------------------------------------------------------
updateModel :: Action -> Effect () () Model Action
updateModel = \case

  Boot -> do
    -- Lift the comment bar above the soft keyboard: Lynx fires the
    -- @keyboardstatuschanged@ global event with (status, height) — on iOS the
    -- height is UIKit points, which are Lynx px 1:1. Subscribed once here on
    -- the BTS (the emitter is a BTS module).
    withSink $ \sink -> do
      cb <- syncCallback2 $ \statusV heightV -> do
        status <- fromJSValUnchecked statusV
        height <- fromJSValUnchecked heightV
        sink (SetKeyboard (if status == ("on" :: MisoString) then height else 0))
      lynxG <- jsg "lynx"
      emitter <- lynxG # "getJSModule" $ ["GlobalEventEmitter" :: MisoString]
      _ <- emitter # "addListener" $ ("keyboardstatuschanged" :: MisoString, cb)
      pure ()
    io (threadDelay splashHold >> pure SplashDone)

  SplashDone ->
    navigate $ \m -> m { screen = ScreenTab, tab = Home }

  -- The "+" tab is a modal flow, not a destination: open the picker over
  -- whatever is showing and leave the selected tab alone.
  SetTab Create ->
    updateModel (Push ScreenPicker)

  SetTab t ->
    navigate $ \m -> m { screen = ScreenTab, tab = t, stack = [] }

  Push s ->
    navigate $ \m -> onEnter s m { screen = s, stack = screen m : stack m }

  Pop ->
    navigate $ \m -> case stack m of
      (s : rest) -> m { screen = s, stack = rest }
      []         -> m { screen = ScreenTab }

  ToggleLike pid ->
    modify $ \m -> m { liked = toggle pid (liked m) }

  ToggleSave pid ->
    modify $ \m -> m { saved = toggle pid (saved m) }

  ToggleFollow uid ->
    modify $ \m -> m { following = toggle uid (following m) }

  -- Double-tap to like: stamp the tap, then compare it with the previous one.
  TapPhoto pid ->
    io (TapPhotoAt pid <$> nowMs)

  TapPhotoAt pid t -> do
    m <- get
    case lastTap m of
      Just (TapMark p t0) | p == pid && t - t0 < doubleTapMs -> do
        modify $ \m' -> m'
          { liked    = if pid `elem` liked m' then liked m' else pid : liked m'
          , bigHeart = Just pid
          , lastTap  = Nothing
          }
        io (threadDelay 900000 >> pure BigHeartOff)
      _ ->
        modify $ \m' -> m' { lastTap = Just (TapMark pid t) }

  BigHeartOff ->
    modify $ \m -> m { bigHeart = Nothing }

  SetSearch q ->
    modify $ \m -> m { searchQuery = q }

  SetCommentDraft s ->
    modify $ \m -> m { commentDraft = s }

  SubmitComment pid -> do
    m <- get
    let draft = MS.strip (commentDraft m)
    if MS.null draft
      then pure ()
      else modify $ \m' -> m'
        { posts = [ if postId p == pid
                      then p { comments = comments p ++ [ Comment (userId you) draft "Just now" ] }
                      else p
                  | p <- posts m' ]
        , commentDraft = ""
        }

  PickPhoto ph ->
    modify $ \m -> m { picked = Just ph }

  SetCaption c ->
    modify $ \m -> m { captionDraft = c }

  -- Share: the new post goes to the top of the feed (and so to your profile
  -- grid), the flow closes back to Home, and a toast confirms it.
  SharePost -> do
    m <- get
    case picked m of
      Nothing -> pure ()
      Just ph -> do
        let post = Post
              { postId    = nextPostId m
              , author    = userId you
              , photos    = [ph]
              , caption   = MS.strip (captionDraft m)
              , location  = ""
              , likeCount = 0
              , likedBy   = 3
              , comments  = []
              , timeAgo   = "Just now"
              }
        navigate $ \m' -> m'
          { posts        = post : posts m'
          , nextPostId   = nextPostId m' + 1
          , picked       = Nothing
          , captionDraft = ""
          , screen       = ScreenTab
          , tab          = Home
          , stack        = []
          , toast        = Just "Your post has been shared."
          }
        io (threadDelay 2500000 >> pure ToastOff)

  ToastOff ->
    modify $ \m -> m { toast = Nothing }

  SetProfileTab i ->
    modify $ \m -> m { profileTab = i }

  ReelsLayout h ->
    modify $ \m -> m { reelsHeight = h }

  MarkNotifsSeen ->
    modify $ \m -> m { notifsSeen = True }

  SetKeyboard h ->
    modify $ \m -> m { kbHeight = h }

  -- Swiper: main-thread handlers (see "MisoGram.Swiper").
  SwipeStart x y ref -> io_ (swipeStart (x, y) ref)
  SwipeMove  x y _   -> io_ (swipeMove (x, y))
  SwipeInit  ref     -> io_ (swipeInit ref)
  SwipeEnd   ref     -> withSink $ \sink ->
    swipeEnd ref >>= maybe (pure ()) (\(key, i) -> sink (Snapped key i))

  -- MTS→BTS: the model is owned by the background thread, so the settled page
  -- is forwarded there; 'SetPage' runs its update on the BTS ('runOnBG').
  Snapped key i ->
    runOnBG (SetPage key i)

  SetPage key i ->
    modify $ \m -> m { pages = PageEntry key i : filter ((/= key) . peKey) (pages m) }

  ResetSwipers ->
    io_ resetSwipers
-----------------------------------------------------------------------------
-- | Every navigation step: apply the change, forget carousel pages, and tell
-- the main thread to forget its track offsets (the elements are recreated).
navigate :: (Model -> Model) -> Effect () () Model Action
navigate f = do
  modify (\m -> (f m) { pages = [] })
  runOnMain ResetSwipers
-----------------------------------------------------------------------------
-- | Per-screen setup when a screen is pushed.
onEnter :: Screen -> Model -> Model
onEnter = \case
  ScreenPicker        -> \m -> m { picked = case picked m of
                                     Nothing -> Just defaultPick
                                     p       -> p }
  ScreenNotifications -> \m -> m { notifsSeen = True }
  ScreenComments _    -> \m -> m { commentDraft = "" }
  ScreenProfile _     -> \m -> m { profileTab = 0 }
  _                   -> id
-----------------------------------------------------------------------------
-- | The wall clock in ms (@Date.now()@). Used only for double-tap timing;
-- @Date@ is guaranteed in every Lynx JS context, whereas @performance.now@ is
-- only sure to exist on the main thread (@lynx.performance@).
nowMs :: IO Double
nowMs = fromJSValUnchecked =<< (jsg "Date" # "now" $ ())
-----------------------------------------------------------------------------
toggle :: Eq a => a -> [a] -> [a]
toggle x xs
  | x `elem` xs = filter (/= x) xs
  | otherwise   = x : xs
-----------------------------------------------------------------------------
