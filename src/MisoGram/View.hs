-----------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE StaticPointers    #-}
-----------------------------------------------------------------------------
-- | Every screen of Misogram, drawn with the native Lynx element vocabulary
-- ('view_', 'text_', 'image_', 'scrollView_', 'input_', …) against the
-- class rules in @styles.css@. Layouts follow Instagram's iOS app closely:
-- the light theme (white, @#262626@ text, @#dbdbdb@ hairlines, @#0095f6@
-- blue, @#ed4956@ heart red), a 44px top bar, a 50px bottom tab bar, 24px
-- line icons, 32px avatars in the feed and 86px on profiles.
--
-- Native @className@ resolves one token per node, so every visual state is
-- its own single class (@.action-icon@ \/ @.action-icon-liked@, @.dot@ \/
-- @.dot-on@, …) rather than a combination.
module MisoGram.View (viewModel) where
-----------------------------------------------------------------------------
import           Data.Maybe (fromMaybe, listToMaybe)
import           Miso hiding (text_, screen)
import qualified Miso.CSS as CSS
import           Miso.Html.Property (className)
import           Miso.Native
import           Miso.Native.X.Element (input_, textarea_)
import qualified Miso.String as MS
-----------------------------------------------------------------------------
import qualified Miso.Native.Element.Image.Property      as IP
import qualified Miso.Native.Element.ScrollView.Property as SP
import qualified Miso.Native.Element.Text.Property       as TP
import qualified Miso.Native.Element.View.Event          as VE
import qualified Miso.Native.Element.View.Property       as VP
import qualified Miso.Native.X.Element.Input.Event       as InE
import qualified Miso.Native.X.Element.Input.Property    as InP
import qualified Miso.Native.X.Element.Textarea.Event    as TaE
import qualified Miso.Native.X.Element.Textarea.Property as TaP
-----------------------------------------------------------------------------
import           MisoGram.Assets
import           MisoGram.Data
import           MisoGram.Swiper (touchPos)
import           MisoGram.Types
-----------------------------------------------------------------------------
type V = View () Model Action
-----------------------------------------------------------------------------
viewModel :: () -> () -> Model -> V
viewModel _ _ m = view_ [ className (if dark then "app-dark" else "app") ]
  ( screenView m
  : [ tabBar m | showsTabBar (screen m) ]
  ++ [ toastView t | Just t <- [toast m] ]
  )
  where
    dark = darkScreen m
-----------------------------------------------------------------------------
-- | Reels and the viewer are black; everything else is white.
darkScreen :: Model -> Bool
darkScreen m = case screen m of
  ScreenTab      -> tab m == Reels
  ScreenViewer{} -> True
  _              -> False
-----------------------------------------------------------------------------
screenView :: Model -> V
screenView m = case screen m of
  ScreenSplash          -> splash
  ScreenTab             -> case tab m of
    Home    -> homeScreen m
    Search  -> searchScreen m
    Create  -> pickerScreen m
    Reels   -> reelsScreen m
    Profile -> profileScreen m you
  ScreenProfile uid     -> profileScreen m (userById uid)
  ScreenViewer set i    -> viewerScreen m set i
  ScreenComments pid    -> commentsScreen m pid
  ScreenNotifications   -> notificationsScreen m
  ScreenPicker          -> pickerScreen m
  ScreenCompose         -> composeScreen m
-----------------------------------------------------------------------------
-- Small building blocks
-----------------------------------------------------------------------------
txt :: MisoString -> MisoString -> V
txt cls s = text_ [ className cls ] [ text s ]

-- | A 24px line icon.
ic :: MisoString -> V
ic name = image_ (icon name) [ className "icon" ]

-- | A 24px line icon that does something when tapped.
icTap :: MisoString -> Action -> V
icTap name a = image_ (icon name) [ className "icon", VE.onTap a ]

spacer :: V
spacer = view_ [ className "spacer" ] []

hairline :: V
hairline = view_ [ className "hairline" ] []

avatarImg :: MisoString -> User -> V
avatarImg cls u = image_ (asset (avatar u)) [ className cls, IP.mode_ "aspectFill" ]

-- | Tapping a name or face opens that account (your own tab for you).
openProfile :: User -> Action
openProfile u
  | isYou u   = SetTab Profile
  | otherwise = Push (ScreenProfile (userId u))

-- | A 44px top bar: a back arrow, a bold title, and whatever goes on the right.
topBar :: MisoString -> [V] -> V
topBar title right = view_ [ className "top-bar" ]
  ( icTap "back" Pop : txt "top-title" title : spacer : right )

-- | @1,234@
fmtNum :: Int -> MisoString
fmtNum n
  | n < 0     = "-" <> fmtNum (negate n)
  | n < 1000  = ms n
  | otherwise = fmtNum (n `div` 1000) <> "," <> pad3 (n `mod` 1000)
  where
    pad3 k | k < 10    = "00" <> ms k
           | k < 100   = "0"  <> ms k
           | otherwise = ms k

-- | Profile-stat style: @48.2K@ above ten thousand, else @1,204@.
fmtStat :: Int -> MisoString
fmtStat n
  | n >= 1000000 = ms (n `div` 1000000) <> "." <> ms ((n `mod` 1000000) `div` 100000) <> "M"
  | n >= 10000   = ms (n `div` 1000) <> "." <> ms ((n `mod` 1000) `div` 100) <> "K"
  | otherwise    = fmtNum n

-- | @2h@ -> @2 hours ago@ (the line under a post).
longAgo :: MisoString -> MisoString
longAgo t
  | t == "Just now" = t
  | otherwise = case (MS.unpack t) of
      [] -> t
      cs -> let unit = last cs
                n    = init cs
                one  = n == "1"
                word = case unit of
                  'm' -> if one then "minute" else "minutes"
                  'h' -> if one then "hour"   else "hours"
                  'd' -> if one then "day"    else "days"
                  'w' -> if one then "week"   else "weeks"
                  _   -> ""
            in if MS.null word then t else ms n <> " " <> word <> " ago"

postsBy :: Model -> UserId -> [Post]
postsBy m uid = filter ((== uid) . author) (posts m)

-- | Every photo someone posted, newest first, with the post it came from.
photosBy :: Model -> UserId -> [(Post, MisoString)]
photosBy m uid = [ (p, ph) | p <- postsBy m uid, ph <- photos p ]

postOfPhoto :: Model -> MisoString -> Maybe Post
postOfPhoto m ph = listToMaybe [ p | p <- posts m, ph `elem` photos p ]

followersOf :: Model -> User -> Int
followersOf m u = followers u + (if userId u `elem` following m then 1 else 0)

pageOf :: Model -> MisoString -> Int -> Int
pageOf m key def = fromMaybe def (listToMaybe [ peIdx e | e <- pages m, peKey e == key ])

chunks :: Int -> [a] -> [[a]]
chunks _ [] = []
chunks n xs = let (h, t) = splitAt n xs in h : chunks n t
-----------------------------------------------------------------------------
-- The swiper track (see "MisoGram.Swiper"). All of its touch handling runs on
-- the main thread; the handlers are top-level so the @static@ forms are closed.
-----------------------------------------------------------------------------
track :: MisoString -> Bool -> Int -> Double -> [V] -> V
track key vertical start size pageViews = view_
  [ className (if vertical then "track-y" else "track-x")
  , textProp "data-key" key
  , textProp "data-n" (ms (length pageViews))
  , textProp "data-axis" (if vertical then "y" else "x")
  , textProp "data-size" (ms size)
  , textProp "data-start" (ms start)
    -- Consume horizontal slides (right ±45°, left 135°–180° / -180°–-135°:
    -- angles live in -180..180, so leftward needs both flanks) so the native
    -- scroller of an enclosing vertical <scroll-view> (the feed) can't claim
    -- the gesture mid-swipe once the finger drifts a few px vertically.
  , VP.consumeSlideEvent_ [ (-180, -135), (-45, 45), (135, 180) ]
  , event (static (VE.onTouchStartMainWith  swipeStartH))
  , event (static (VE.onTouchMoveMainWith   swipeMoveH))
  , event (static (VE.onTouchEndMainWith    swipeEndH))
  , event (static (VE.onTouchCancelMainWith swipeEndH))
  , event (static (VE.onLayoutChangeMainWith swipeInitH))
  ]
  pageViews

swipeStartH :: VE.TouchEvent -> Model -> DOMRef -> Action
swipeStartH t _ ref = let (x, y) = touchPos t in SwipeStart x y ref

swipeMoveH :: VE.TouchEvent -> Model -> DOMRef -> Action
swipeMoveH t _ ref = let (x, y) = touchPos t in SwipeMove x y ref

swipeEndH :: VE.TouchEvent -> Model -> DOMRef -> Action
swipeEndH _ _ ref = SwipeEnd ref

swipeInitH :: VE.LayoutChangeDetailEvent -> Model -> DOMRef -> Action
swipeInitH _ _ ref = SwipeInit ref
-----------------------------------------------------------------------------
-- Splash
-----------------------------------------------------------------------------
splash :: V
splash = view_ [ className "splash" ]
  [ spacer
  , image_ (asset "brand/logo.png") [ className "splash-logo", IP.mode_ "aspectFit" ]
  , spacer
  , txt "splash-from" "from"
  , txt "splash-miso" "miso"
  ]
-----------------------------------------------------------------------------
-- Home feed
-----------------------------------------------------------------------------
homeScreen :: Model -> V
homeScreen m = view_ [ className "screen" ]
  [ view_ [ className "top-bar" ]
    [ image_ (asset "brand/wordmark.png") [ className "wordmark", IP.mode_ "aspectFit" ]
    , spacer
    , view_ [ className "icon-wrap", VE.onTap (Push ScreenNotifications) ]
      ( ic "heart" : [ view_ [ className "badge-dot" ] [] | not (notifsSeen m) ] )
    , view_ [ className "icon-wrap" ] [ ic "messenger" ]
    ]
  , scrollView_
    [ className "scroll", SP.scrollOrientation_ "vertical", SP.enableScroll_ True, SP.bounces_ True ]
    ( storiesBar m
    : hairline
    : map (postCard m) (posts m)
    ++ [ view_ [ className "feed-end" ]
         [ ic "check", txt "feed-end-title" "You're all caught up"
         , txt "feed-end-sub" "You've seen all new posts from the past 3 days." ]
       ]
    )
  ]
-----------------------------------------------------------------------------
storiesBar :: Model -> V
storiesBar _ = scrollView_
  [ className "stories", SP.scrollOrientation_ "horizontal", SP.enableScroll_ True, SP.bounces_ True ]
  (map story storyUsers)
  where
    story u
      | isYou u = view_ [ className "story", VE.onTap (Push ScreenPicker) ]
          [ view_ [ className "story-own" ]
            [ avatarImg "story-avatar" u
            , image_ (icon "add-circle-blue") [ className "story-plus" ]
            ]
          , txt "story-name" "Your story"
          ]
      | otherwise = view_ [ className "story", VE.onTap (openProfile u) ]
          [ view_ [ className "story-ring" ]
            [ view_ [ className "story-gap" ] [ avatarImg "story-avatar" u ] ]
          , txt "story-name" (handle u)
          ]
-----------------------------------------------------------------------------
postCard :: Model -> Post -> V
postCard m post@Post{..} = view_ [ className "post" ]
  [ view_ [ className "post-head" ]
    [ view_ [ VE.onTap (openProfile u) ] [ avatarImg "avatar-32" u ]
    , view_ [ className "post-head-text", VE.onTap (openProfile u) ]
      [ view_ [ className "row" ]
        ( txt "username" (handle u)
        : [ image_ (icon "verified-blue") [ className "verified" ] | verified u ] )
      , if MS.null location then view_ [] [] else txt "location" location
      ]
    , spacer
    , ic "more"
    ]
  , postMedia m post
  , view_ [ className "actions" ]
    ( [ image_ (icon (if isLiked then "heart-red" else "heart"))
          [ className (if isLiked then "action-icon-liked" else "action-icon"), VE.onTap (ToggleLike postId) ]
      , image_ (icon "comment") [ className "action-icon", VE.onTap (Push (ScreenComments postId)) ]
      , image_ (icon "send") [ className "action-icon" ]
      , spacer
      , image_ (icon (if isSaved then "bookmark-fill" else "bookmark"))
          [ className "action-icon-r", VE.onTap (ToggleSave postId) ]
      ]
      ++ [ dots (length photos) (pageOf m (carouselKey postId) 0) | length photos > 1 ]
    )
  , view_ [ className "post-body" ]
    ( likesLine
    : text_ [ className "caption" ]
        [ text_ [ className "b", VE.onTap (openProfile u) ] [ text (handle u) ]
        , text (" " <> caption)
        ]
    : [ view_ [ VE.onTap (Push (ScreenComments postId)) ]
        [ txt "muted" ("View all " <> ms (length comments) <> " comments") ]
      | not (null comments) ]
    ++ [ txt "time" (longAgo timeAgo) ]
    )
  ]
  where
    u       = userById author
    isLiked = postId `elem` liked m
    isSaved = postId `elem` saved m
    total   = likeCount + (if isLiked then 1 else 0)
    likesLine
      | total == 0 = txt "b" "Be the first to like this"
      | total == 1 = text_ [ className "likes" ] [ text "Liked by ", text_ [ className "b" ] [ text (whoLiked) ] ]
      | otherwise  = text_ [ className "likes" ]
          [ text "Liked by ", text_ [ className "b" ] [ text whoLiked ]
          , text " and ", text_ [ className "b" ] [ text (fmtNum (total - 1) <> " others") ] ]
    whoLiked | isLiked && likeCount == 0 = "you"
             | otherwise = handle (userById likedBy)

carouselKey :: PostId -> MisoString
carouselKey pid = "c" <> ms pid

-- | The square photo area: a single photo, or a swipeable carousel with a
-- @1/3@ counter. A double tap likes it (with the big white heart).
postMedia :: Model -> Post -> V
postMedia m Post{..} = view_ [ className "media", VE.onTap (TapPhoto postId) ]
  ( (case photos of
       [one] -> [ image_ (photo one) [ className "media-img", IP.mode_ "aspectFill" ] ]
       many  ->
         [ track (carouselKey postId) False 0 0
             [ view_ [ className "page-x" ] [ image_ (photo ph) [ className "media-img", IP.mode_ "aspectFill" ] ]
             | ph <- many ]
         , txt "counter" (ms (pageOf m (carouselKey postId) 0 + 1) <> "/" <> ms (length many))
         ])
  ++ [ image_ (icon "heart-red-big")
         [ className (if bigHeart m == Just postId then "big-heart-on" else "big-heart") ] ]
  )

-- | The carousel page dots, centred in the actions row.
dots :: Int -> Int -> V
dots n cur = view_ [ className "dots" ]
  [ view_ [ className (if i == cur then "dot-on" else "dot") ] [] | i <- [0 .. n - 1] ]
-----------------------------------------------------------------------------
-- Search / explore
-----------------------------------------------------------------------------
searchScreen :: Model -> V
searchScreen m = view_ [ className "screen" ]
  [ view_ [ className "search-wrap" ]
    [ view_ [ className "search-bar" ]
      [ image_ (icon "search-gray") [ className "icon-sm" ]
      , input_
        [ className "search-input"
        , InP.placeholder_ "Search"
        , textProp "value" q
        , InE.onInput (SetSearch . InE.inputValue)
        ]
      ]
    ]
  , scrollView_ [ className "scroll", SP.scrollOrientation_ "vertical", SP.enableScroll_ True ]
      (if MS.null (MS.strip q) then [ photoGrid ViewerExplore exploreOrder ] else results)
  ]
  where
    q     = searchQuery m
    needle = MS.toLower (MS.strip q)
    hit s = needle `MS.isInfixOf` MS.toLower s
    matchedUsers = [ u | u <- users, hit (handle u) || hit (fullName u) ]
    matchedPhotos = [ ph | p <- posts m, hit (caption p) || hit (handle (userById (author p))), ph <- take 1 (photos p) ]
    results =
      [ txt "section" "Accounts" | not (null matchedUsers) ]
      ++ map userRow matchedUsers
      ++ [ txt "section" "Posts" | not (null matchedPhotos) ]
      ++ [ photoGrid ViewerExplore matchedPhotos | not (null matchedPhotos) ]
      ++ [ txt "empty" ("No results found for \"" <> q <> "\"") | null matchedUsers && null matchedPhotos ]
    userRow u = view_ [ className "user-row", VE.onTap (openProfile u) ]
      [ avatarImg "avatar-44" u
      , view_ [ className "col" ]
        [ view_ [ className "row" ] ( txt "username" (handle u) : [ image_ (icon "verified-blue") [ className "verified" ] | verified u ] )
        , txt "muted" (fullName u <> " · " <> fmtStat (followersOf m u) <> " followers")
        ]
      ]

-- | A three-column grid of square tiles; tapping one opens the viewer at it.
photoGrid :: ViewerSet -> [MisoString] -> V
photoGrid set phs = view_ [ className "grid" ]
  [ view_ [ className "grid-row" ]
    ( [ view_ [ className "tile", VE.onTap (Push (ScreenViewer set i)) ]
        [ image_ (photo ph) [ className "tile-img", IP.mode_ "aspectFill" ] ]
      | (i, ph) <- row ]
      ++ replicate (3 - length row) (view_ [ className "tile-empty" ] []) )
  | row <- chunks 3 (zip [0 ..] phs)
  ]
-----------------------------------------------------------------------------
-- Profile
-----------------------------------------------------------------------------
profileScreen :: Model -> User -> V
profileScreen m u = view_ [ className "screen" ]
  [ if isYou u
      then view_ [ className "top-bar" ]
        [ txt "top-title" (handle u), ic "chevron-down", spacer
        , view_ [ className "icon-wrap" ] [ icTap "plus" (Push ScreenPicker) ]
        , view_ [ className "icon-wrap" ] [ ic "menu" ] ]
      else topBar (handle u) [ ic "more" ]
  , scrollView_ [ className "scroll", SP.scrollOrientation_ "vertical", SP.enableScroll_ True, SP.bounces_ True ]
    [ view_ [ className "profile-top" ]
      [ if isYou u
          then view_ [ className "profile-avatar-wrap" ] [ avatarImg "avatar-86" u ]
          else view_ [ className "profile-ring" ] [ view_ [ className "story-gap" ] [ avatarImg "avatar-86" u ] ]
      , stat (ms (length myPosts)) "posts"
      , stat (fmtStat (followersOf m u)) "followers"
      , stat (fmtStat (followingN u)) "following"
      ]
    , view_ [ className "profile-bio" ]
      ( txt "b" (fullName u) : map (txt "bio") (MS.lines (bio u)) )
    , view_ [ className "profile-buttons" ]
      ( if isYou u
          then [ button "btn-gray" "Edit profile" Nothing
               , button "btn-gray" "Share profile" Nothing
               ]
          else [ if isFollowing
                   then button "btn-gray" "Following" (Just (ToggleFollow (userId u)))
                   else button "btn-blue" "Follow" (Just (ToggleFollow (userId u)))
               , button "btn-gray" "Message" Nothing
               ] )
    , scrollView_ [ className "highlights", SP.scrollOrientation_ "horizontal", SP.enableScroll_ True ]
      ( [ view_ [ className "highlight" ]
          [ view_ [ className "highlight-ring" ] [ image_ (photo ph) [ className "highlight-img", IP.mode_ "aspectFill" ] ]
          , txt "story-name" label ]
        | (label, ph) <- zip highlightNames (map snd myPhotos) ]
        ++ [ view_ [ className "highlight" ]
             [ view_ [ className "highlight-new" ] [ ic "plus" ], txt "story-name" "New" ]
           | isYou u ] )
    , view_ [ className "profile-tabs" ]
      [ ptab 0 "grid", ptab 1 "reels", ptab 2 "tagged" ]
    , case profileTab m of
        0 -> photoGrid (ViewerUser (userId u)) (map snd myPhotos)
        1 -> emptyState "reels" "No reels yet" "Reels you share will appear here."
        _ -> emptyState "tagged" "No photos" ("When people tag " <> handle u <> " in photos, they'll appear here.")
    ]
  ]
  where
    myPosts     = postsBy m (userId u)
    myPhotos    = photosBy m (userId u)
    isFollowing = userId u `elem` following m
    stat n label = view_ [ className "stat" ] [ txt "stat-n" n, txt "stat-label" label ]
    button cls label act = view_ ( className cls : [ VE.onTap a | Just a <- [act] ] )
      [ txt (if cls == "btn-blue" then "btn-text-white" else "btn-text") label ]
    ptab i name = view_
      [ className (if profileTab m == i then "profile-tab-on" else "profile-tab"), VE.onTap (SetProfileTab i) ]
      [ ic (if profileTab m == i then name else name <> "-gray") ]
    highlightNames = [ "Tonkotsu", "Tokyo", "Home cook", "Kyushu", "Hokkaido", "Kansai" ]
    emptyState iconName title sub = view_ [ className "empty-state" ]
      [ view_ [ className "empty-ring" ] [ image_ (icon iconName) [ className "icon-lg" ] ]
      , txt "empty-title" title
      , txt "empty" sub
      ]
-----------------------------------------------------------------------------
-- Full-screen viewer: swipe between someone's pictures
-----------------------------------------------------------------------------
viewerScreen :: Model -> ViewerSet -> Int -> V
viewerScreen m set start = view_ [ className "viewer" ]
  [ view_ [ className "top-bar-dark" ]
    [ icTap "back-white" Pop
    , view_ [ className "col" ] [ txt "viewer-sub" subtitle, txt "viewer-title" "Posts" ]
    , spacer
    , txt "viewer-count" (ms (cur + 1) <> " / " <> ms (length items))
    ]
  , view_ [ className "viewer-body" ]
    [ track "viewer-track" False start 0
        [ view_ [ className "page-x-fill" ] [ image_ (photo ph) [ className "fill-img", IP.mode_ "aspectFit" ] ]
        | (_, ph) <- items ]
    ]
  , case drop cur items of
      ((Just p, _) : _) -> viewerFooter p
      _                 -> view_ [] []
  ]
  where
    items :: [(Maybe Post, MisoString)]
    items = case set of
      ViewerUser uid -> [ (Just p, ph) | (p, ph) <- photosBy m uid ]
      ViewerExplore  -> [ (postOfPhoto m ph, ph) | ph <- exploreOrder ]
    cur = min (length items - 1) (max 0 (pageOf m "viewer-track" start))
    subtitle = case set of
      ViewerUser uid -> MS.toUpper (handle (userById uid))
      ViewerExplore  -> "EXPLORE"
    viewerFooter Post{..} =
      let u = userById author
          isLiked = postId `elem` liked m
      in view_ [ className "viewer-footer" ]
        [ view_ [ className "actions" ]
          [ image_ (icon (if isLiked then "heart-red" else "heart-white"))
              [ className (if isLiked then "action-icon-liked" else "action-icon"), VE.onTap (ToggleLike postId) ]
          , image_ (icon "comment-white") [ className "action-icon", VE.onTap (Push (ScreenComments postId)) ]
          , image_ (icon "send-white") [ className "action-icon" ]
          , spacer
          , image_ (icon (if postId `elem` saved m then "bookmark-fill-white" else "bookmark-white"))
              [ className "action-icon-r", VE.onTap (ToggleSave postId) ]
          ]
        , txt "likes-white" (fmtNum (likeCount + (if isLiked then 1 else 0)) <> " likes")
        , text_ [ className "caption-white", TP.textMaxLine_ 2 ]
            [ text_ [ className "b-white" ] [ text (handle u) ], text (" " <> caption) ]
        ]
-----------------------------------------------------------------------------
-- Comments
-----------------------------------------------------------------------------
commentsScreen :: Model -> PostId -> V
commentsScreen m pid = view_ [ className "screen" ]
  [ topBar "Comments" [ ic "send" ]
  , scrollView_ [ className "scroll", SP.scrollOrientation_ "vertical", SP.enableScroll_ True ]
      ( case post of
          Nothing -> []
          Just p  ->
            captionRow p
            : hairline
            : map commentRow (comments p)
            ++ [ txt "empty" "No comments yet. Start the conversation." | null (comments p) ] )
    -- The keyboard overlays the LynxView, so lift the bar above it by the
    -- height from Lynx's keyboardstatuschanged event (0 when hidden).
  , view_ ( className "comment-bar"
          : [ CSS.style_ [ CSS.marginBottom (ms (round (kbHeight m) :: Int) <> "px") ]
            | kbHeight m > 0 ] )
    [ avatarImg "avatar-32" you
    , input_
      [ className "comment-input"
      , InP.placeholder_ ("Add a comment for " <> maybe "" (handle . userById . author) post <> "…")
      , textProp "value" (commentDraft m)
      , InE.onInput (SetCommentDraft . InE.inputValue)
      , InE.onConfirm (const (SubmitComment pid))
      ]
    , view_ [ VE.onTap (SubmitComment pid) ]
      [ txt (if MS.null (MS.strip (commentDraft m)) then "post-btn-off" else "post-btn") "Post" ]
    ]
  ]
  where
    post = listToMaybe [ p | p <- posts m, postId p == pid ]
    captionRow Post{..} =
      let u = userById author
      in view_ [ className "comment-row" ]
        [ view_ [ VE.onTap (openProfile u) ] [ avatarImg "avatar-32" u ]
        , view_ [ className "comment-body" ]
          [ text_ [ className "caption" ] [ text_ [ className "b" ] [ text (handle u) ], text (" " <> caption) ]
          , txt "muted" (longAgo timeAgo)
          ]
        ]
    commentRow Comment{..} =
      let u = userById commentUser
      in view_ [ className "comment-row" ]
        [ view_ [ VE.onTap (openProfile u) ] [ avatarImg "avatar-32" u ]
        , view_ [ className "comment-body" ]
          [ text_ [ className "caption" ] [ text_ [ className "b" ] [ text (handle u) ], text (" " <> commentText) ]
          , view_ [ className "row" ] [ txt "muted" commentTime, txt "muted-b" "Reply" ]
          ]
        , image_ (icon "heart-gray") [ className "icon-xs" ]
        ]
-----------------------------------------------------------------------------
-- Notifications
-----------------------------------------------------------------------------
notificationsScreen :: Model -> V
notificationsScreen m = view_ [ className "screen" ]
  [ topBar "Notifications" []
  , scrollView_ [ className "scroll", SP.scrollOrientation_ "vertical", SP.enableScroll_ True ]
      ( txt "section" "Today"
      : map notifRow today
      ++ txt "section" "This week"
      : map notifRow week )
  ]
  where
    (today, week) = splitAt 4 notifications
    notifRow Notif{..} =
      let u = userById notifUser
          verb = case notifKind of
            NLiked         -> " liked your photo."
            NFollowed      -> " started following you."
            NCommented s   -> " commented: " <> s
            NMentioned s   -> " mentioned you in a comment: " <> s
      in view_ [ className "notif-row" ]
        [ view_ [ VE.onTap (openProfile u) ] [ avatarImg "avatar-44" u ]
        , text_ [ className "notif-text" ]
          [ text_ [ className "b" ] [ text (handle u) ]
          , text verb
          , text_ [ className "muted" ] [ text (" " <> notifTime) ]
          ]
        , case (notifKind, notifPhoto) of
            (NFollowed, _) ->
              if notifUser `elem` following m
                then view_ [ className "btn-gray-sm", VE.onTap (ToggleFollow notifUser) ] [ txt "btn-text" "Following" ]
                else view_ [ className "btn-blue-sm", VE.onTap (ToggleFollow notifUser) ] [ txt "btn-text-white" "Follow" ]
            (_, Just ph) -> image_ (photo ph) [ className "notif-thumb", IP.mode_ "aspectFill" ]
            _            -> view_ [] []
        ]
-----------------------------------------------------------------------------
-- New post, step 1: pick a photo
-----------------------------------------------------------------------------
pickerScreen :: Model -> V
pickerScreen m = view_ [ className "screen" ]
  [ view_ [ className "top-bar" ]
    [ icTap "close" Pop, txt "top-title" "New post", spacer
    , view_ [ VE.onTap (Push ScreenCompose) ] [ txt "blue-btn" "Next" ]
    ]
  , scrollView_ [ className "scroll", SP.scrollOrientation_ "vertical", SP.enableScroll_ True ]
    [ view_ [ className "media" ] [ image_ (photo sel) [ className "media-img", IP.mode_ "aspectFill" ] ]
    , view_ [ className "picker-bar" ]
      [ txt "b" "Recents", ic "chevron-down", spacer
      , view_ [ className "picker-cam" ] [ ic "camera" ]
      ]
    , view_ [ className "grid" ]
      [ view_ [ className "grid-row" ]
        [ view_ [ className (if ph == sel then "tile-sel" else "tile"), VE.onTap (PickPhoto ph) ]
          [ image_ (photo ph) [ className "tile-img", IP.mode_ "aspectFill" ] ]
        | ph <- row ]
      | row <- chunks 4 cameraRoll ]
    ]
  ]
  where
    sel = fromMaybe defaultPick (picked m)
-----------------------------------------------------------------------------
-- New post, step 2: caption and share
-----------------------------------------------------------------------------
composeScreen :: Model -> V
composeScreen m = view_ [ className "screen" ]
  [ view_ [ className "top-bar" ]
    [ icTap "back" Pop, txt "top-title" "New post", spacer
    , view_ [ VE.onTap SharePost ] [ txt "blue-btn" "Share" ]
    ]
  , scrollView_ [ className "scroll", SP.scrollOrientation_ "vertical", SP.enableScroll_ True ]
    ( view_ [ className "compose-row" ]
      [ image_ (photo sel) [ className "compose-thumb", IP.mode_ "aspectFill" ]
      , textarea_
        [ className "caption-input"
        , TaP.placeholder_ "Write a caption…"
        , textProp "value" (captionDraft m)
        , TaE.onInput (SetCaption . TaE.textareaValue)
        ]
      ]
    : hairline
    : map settingRow [ "Add location", "Tag people", "Add music", "Audience", "Also share to", "Advanced settings" ]
    )
  ]
  where
    sel = fromMaybe defaultPick (picked m)
    settingRow label = view_ [ className "setting-row" ]
      [ txt "setting" label, spacer, ic "chevron-down" ]
-----------------------------------------------------------------------------
-- Reels: swipe vertically between everyone's pictures
-----------------------------------------------------------------------------
reelsScreen :: Model -> V
reelsScreen m = view_ [ className "reels", VE.onLayoutChange (ReelsLayout . VE.layoutChangeDetailEventHeight) ]
  [ track "reels-track" True 0 (reelsHeight m) (map reel (posts m))
  , view_ [ className "reels-head" ] [ txt "reels-title" "Reels", spacer, ic "camera-white" ]
  ]
  where
    reel Post{..} =
      let u = userById author
          isLiked = postId `elem` liked m
          isFollowing = userId u `elem` following m || isYou u
      in view_ [ className "page-y" ]
        [ image_ (photo (fromMaybe defaultPick (listToMaybe photos))) [ className "fill-img", IP.mode_ "aspectFill" ]
        , view_ [ className "reel-shade" ] []
        , view_ [ className "reel-rail" ]
          [ image_ (icon (if isLiked then "heart-red" else "heart-white")) [ className "rail-icon", VE.onTap (ToggleLike postId) ]
          , txt "rail-n" (fmtStat (likeCount + (if isLiked then 1 else 0)))
          , image_ (icon "comment-white") [ className "rail-icon", VE.onTap (Push (ScreenComments postId)) ]
          , txt "rail-n" (ms (length comments))
          , image_ (icon "send-white") [ className "rail-icon" ]
          , image_ (icon "more-v-white") [ className "rail-icon" ]
          ]
        , view_ [ className "reel-info" ]
          [ view_ [ className "row" ]
            ( view_ [ VE.onTap (openProfile u) ] [ avatarImg "avatar-32-ring" u ]
            : txt "username-white" (handle u)
            : [ view_ [ className "follow-pill", VE.onTap (ToggleFollow (userId u)) ] [ txt "follow-pill-text" "Follow" ]
              | not isFollowing ] )
          , text_ [ className "caption-white", TP.textMaxLine_ 2 ] [ text caption ]
          , view_ [ className "row" ] [ image_ (icon "music-white") [ className "icon-xs" ], txt "music-line" ("Original audio · " <> handle u) ]
          ]
        ]
-----------------------------------------------------------------------------
-- Bottom tab bar
-----------------------------------------------------------------------------
tabBar :: Model -> V
tabBar m = view_ [ className (if dark then "tabbar-dark" else "tabbar") ]
  [ tabIcon Home   "home"
  , tabIcon Search "search"
  , tabIcon Create "plus"
  , tabIcon Reels  "reels"
  , view_ [ className "tab", VE.onTap (SetTab Profile) ]
    [ avatarImg (if onTab Profile then "tab-avatar-on" else "tab-avatar") you ]
  ]
  where
    dark = darkScreen m
    onTab t = screen m == ScreenTab && tab m == t
    tabIcon t name =
      let filled = onTab t && t /= Create
          nm = name <> (if filled then "-fill" else "") <> (if dark then "-white" else "")
      in view_ [ className "tab", VE.onTap (SetTab t) ] [ image_ (icon nm) [ className "icon" ] ]
-----------------------------------------------------------------------------
toastView :: MisoString -> V
toastView s = view_ [ className "toast" ] [ txt "toast-text" s ]
-----------------------------------------------------------------------------
