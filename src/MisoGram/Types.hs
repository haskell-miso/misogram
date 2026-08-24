-----------------------------------------------------------------------------
{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings  #-}
-----------------------------------------------------------------------------
-- | The domain model of Misogram: users, posts, comments, notifications, the
-- navigation state, and the app-wide 'Model' \/ 'Action' pair.
--
-- Everything here derives 'ToJSON' \/ 'FromJSON' because miso-native ships the
-- BTS-owned model to the MTS as JSON (see "Miso.Native"), and actions cross the
-- thread boundary the same way ('Miso.Effect.runOnBG' \/ 'Miso.Effect.runOnMain').
module MisoGram.Types where
-----------------------------------------------------------------------------
import           GHC.Generics (Generic)
import           Miso (DOMRef)
import           Miso.JSON (ToJSON, FromJSON)
import           Miso.Native.MainThread () -- ToJSON / FromJSON DOMRef
import           Miso.String (MisoString)
-----------------------------------------------------------------------------
type UserId = Int
type PostId = Int
-----------------------------------------------------------------------------
data User = User
  { userId     :: UserId
  , handle     :: MisoString   -- ^ @ramen_ronin@
  , fullName   :: MisoString
  , bio        :: MisoString   -- ^ newline-separated lines
  , avatar     :: MisoString   -- ^ asset name, e.g. @avatars/a0.jpg@
  , verified   :: Bool
  , followers  :: Int
  , followingN :: Int
  , isYou      :: Bool
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)
-----------------------------------------------------------------------------
data Comment = Comment
  { commentUser :: UserId
  , commentText :: MisoString
  , commentTime :: MisoString
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)
-----------------------------------------------------------------------------
data Post = Post
  { postId    :: PostId
  , author    :: UserId
  , photos    :: [MisoString]  -- ^ asset names; >1 makes a swipeable carousel
  , caption   :: MisoString
  , location  :: MisoString    -- ^ empty for none
  , likeCount :: Int
  , likedBy   :: UserId        -- ^ the friend named in "Liked by … and N others"
  , comments  :: [Comment]
  , timeAgo   :: MisoString    -- ^ @2h@, @1d@, @1w@
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)
-----------------------------------------------------------------------------
data NotifKind
  = NLiked
  | NFollowed
  | NCommented MisoString
  | NMentioned MisoString
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)
-----------------------------------------------------------------------------
data Notif = Notif
  { notifUser  :: UserId
  , notifKind  :: NotifKind
  , notifTime  :: MisoString
  , notifPhoto :: Maybe MisoString
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)
-----------------------------------------------------------------------------
-- | The five bottom-bar tabs, in Instagram's order.
data Tab = Home | Search | Create | Reels | Profile
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)
-----------------------------------------------------------------------------
-- | Which set of pictures the full-screen viewer swipes across.
data ViewerSet
  = ViewerUser UserId   -- ^ everything one person posted
  | ViewerExplore       -- ^ the explore grid
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)
-----------------------------------------------------------------------------
data Screen
  = ScreenSplash
  | ScreenTab                    -- ^ whatever 'tab' says
  | ScreenProfile UserId         -- ^ somebody else's profile
  | ScreenViewer ViewerSet Int   -- ^ full-screen swiper, opened at this index
  | ScreenComments PostId
  | ScreenNotifications
  | ScreenPicker                 -- ^ new post, step 1: pick a photo
  | ScreenCompose                -- ^ new post, step 2: caption + share
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)
-----------------------------------------------------------------------------
-- | A carousel's current page, keyed by the track element's @id@.
data PageEntry = PageEntry
  { peKey :: MisoString
  , peIdx :: Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)
-----------------------------------------------------------------------------
-- | The previous tap on a feed photo, for double-tap-to-like detection.
data TapMark = TapMark
  { tapPost :: PostId
  , tapTime :: Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)
-----------------------------------------------------------------------------
data Model = Model
  { screen       :: Screen
  , stack        :: [Screen]       -- ^ screens under the current one (back stack)
  , tab          :: Tab
  , posts        :: [Post]         -- ^ the feed, newest first
  , liked        :: [PostId]
  , saved        :: [PostId]
  , following    :: [UserId]
  , pages        :: [PageEntry]    -- ^ carousel pages (id -> index)
  , bigHeart     :: Maybe PostId   -- ^ the double-tap heart currently popping
  , lastTap      :: Maybe TapMark
  , commentDraft :: MisoString
  , searchQuery  :: MisoString
  , picked       :: Maybe MisoString
  , captionDraft :: MisoString
  , nextPostId   :: Int
  , toast        :: Maybe MisoString
  , reelsHeight  :: Double         -- ^ measured height of the reels pager
  , profileTab   :: Int            -- ^ 0 grid, 1 reels, 2 tagged
  , notifsSeen   :: Bool
  } deriving stock (Eq, Generic)
    deriving anyclass (ToJSON, FromJSON)
-----------------------------------------------------------------------------
data Action
  = Boot
  -- ^ fired on mount: hold the splash, then 'SplashDone'
  | SplashDone
  | SetTab Tab
  | Push Screen
  | Pop
  | ToggleLike PostId
  | ToggleSave PostId
  | ToggleFollow UserId
  | TapPhoto PostId
  -- ^ a tap on a feed photo; stamps the time and becomes 'TapPhotoAt'
  | TapPhotoAt PostId Double
  | BigHeartOff
  | SetSearch MisoString
  | SetCommentDraft MisoString
  | SubmitComment PostId
  | PickPhoto MisoString
  | SetCaption MisoString
  | SharePost
  | ToastOff
  | SetProfileTab Int
  | ReelsLayout Double
  | MarkNotifsSeen
    -- swiper: main-thread (MTS) handlers, see "MisoGram.Swiper"
  | SwipeStart Double Double DOMRef
  | SwipeMove Double Double DOMRef
  | SwipeEnd DOMRef
  | SwipeInit DOMRef
  | Snapped MisoString Int
  -- ^ MTS -> BTS: the track with this id settled on this page
  | SetPage MisoString Int
  -- ^ BTS: record a carousel's page (repaints its dots / counter)
  | ResetSwipers
  -- ^ BTS -> MTS: forget every track's offset (the elements were recreated)
  deriving stock (Generic)
  deriving anyclass (ToJSON, FromJSON)
-----------------------------------------------------------------------------
-- | Which tabs keep the bottom bar on screen.
showsTabBar :: Screen -> Bool
showsTabBar ScreenTab         = True
showsTabBar (ScreenProfile _) = True
showsTabBar _                 = False
-----------------------------------------------------------------------------
