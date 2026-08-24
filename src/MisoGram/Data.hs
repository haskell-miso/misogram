-----------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
-----------------------------------------------------------------------------
-- | The fake social graph: eight accounts (one of them you), seventeen posts
-- across twenty-three bowls of ramen, their comments, and a notifications
-- inbox. The photos are CC-licensed Wikimedia Commons uploads (see
-- @assets/photos/CREDITS.json@); the people are invented.
module MisoGram.Data
  ( users
  , you
  , userById
  , initialPosts
  , notifications
  , exploreOrder
  , cameraRoll
  , defaultPick
  , storyUsers
  ) where
-----------------------------------------------------------------------------
import           Miso.String (MisoString, ms)
import           MisoGram.Types
-----------------------------------------------------------------------------
users :: [User]
users =
  [ User 0 "ramen_ronin"   "Kenji Watanabe"  "🍜 tonkotsu evangelist · Fukuoka → Tokyo\n1,000 bowls project: 412/1000"   "avatars/a0.jpg" True  48213 312 False
  , User 1 "miso.mika"     "Mika Sato"       "miso ramen, mostly 🌽🧈\nSapporo born, Tokyo based"                          "avatars/a1.jpg" False 12904 540 False
  , User 2 "hakata_hana"   "Hana Kimura"     "thin noodles, katame please 🍥\nkaedama enthusiast"                          "avatars/a2.jpg" False  8721 233 False
  , User 3 "sapporo_sam"   "Sam Okada"       "butter corn miso is a lifestyle · Hokkaido 🏔"                               "avatars/a3.jpg" False  5308 411 False
  , User 4 "abura_akira"   "Akira Nakamura"  "abura soba & tsukemen · no soup no problem"                                  "avatars/a4.jpg" False  3109 198 False
  , User 5 "kumamoto_kuma" "Kuma Yoshida"    "black garlic oil 🖤 Kumamoto / Kyushu\nramen tours: link in bio"             "avatars/a5.jpg" True  19870  87 False
  , User 6 "veggie_yumi"   "Yumi Tanaka"     "plant-based ramen recipes 🌱\nrecipe developer · cookbook out now"           "avatars/a6.jpg" False 27650 602 False
  , User 7 "miso_dev"      "Miso Dev"        "Haskell 🍜 building an Instagram out of ramen\nmiso-native · lynxjs · ghc-js" "avatars/a7.jpg" False  1204  87 True
  ]
-----------------------------------------------------------------------------
-- | The signed-in account.
you :: User
you = users !! 7
-----------------------------------------------------------------------------
userById :: UserId -> User
userById i = case filter ((== i) . userId) users of
  (u : _) -> u
  []      -> you
-----------------------------------------------------------------------------
-- | The accounts whose stories sit in the bar under the header (you first).
storyUsers :: [User]
storyUsers = you : filter (not . isYou) users
-----------------------------------------------------------------------------
p :: Int -> MisoString
p n = "p" <> (if n < 10 then "0" else "") <> ms n <> ".jpg"
-----------------------------------------------------------------------------
-- | The feed, newest first.
initialPosts :: [Post]
initialPosts =
  [ Post 1 0 [p 0, p 6, p 22]
      "Tonkotsu trilogy 🐷 Ikkousha → Hakata Choten → Goemon. Which broth wins? #tonkotsu #ramen"
      "Fukuoka, Japan" 2431 3
      [ Comment 1 "the third one 😮" "1h", Comment 2 "katame + kaedama or it didn't happen" "1h"
      , Comment 5 "black garlic oil on #3 would end me" "45m" ] "2h"
  , Post 2 1 [p 1]
      "Butter. Corn. Miso. That's the post. 🧈🌽"
      "Sapporo, Hokkaido" 1876 0
      [ Comment 3 "this is the way" "3h", Comment 6 "recipe pls 🙏" "2h" ] "4h"
  , Post 3 6 [p 17]
      "Plant-based shoyu with roasted squash & charred scallion. No pork, no problem 🌱 Recipe on the blog. #veganramen"
      "Kyoto, Japan" 4102 1
      [ Comment 1 "need this" "4h", Comment 4 "the squash 😍" "3h" ] "5h"
  , Post 4 4 [p 9, p 4]
      "Soupless Sunday: abura soba, then tsukemen for dessert 🍜🍜 #aburasoba #tsukemen"
      "Nakano, Tokyo" 934 2
      [ Comment 0 "dessert tsukemen is elite behaviour" "6h" ] "7h"
  , Post 5 2 [p 3]
      "Shio so clear you can see the future in it 🔮 chashu on point"
      "Hakodate" 1207 6
      [ Comment 1 "clean!!" "8h", Comment 3 "the egg tho" "8h" ] "9h"
  , Post 6 3 [p 7, p 19]
      "Sapporo miso vs Asahikawa shoyu. The Hokkaido derby 🏔"
      "Susukino, Sapporo" 2210 1
      [ Comment 0 "Asahikawa's lard layer keeps it hot forever" "11h", Comment 2 "sapporo. next question" "10h" ] "12h"
  , Post 7 5 [p 14]
      "Mayu (black garlic oil) makes everything better 🖤 Kumamoto style"
      "Kumamoto, Japan" 3345 0
      [ Comment 4 "that colour 🖤" "1d" ] "1d"
  , Post 8 0 [p 13]
      "Ramen Jiro. Yasai mashi, ninniku mashi. I regret nothing. 🥬🧄 #jiro"
      "Mita, Tokyo" 5120 4
      [ Comment 3 "bean sprout mountain" "1d", Comment 1 "you ok?" "1d", Comment 5 "legend" "1d" ] "1d"
  , Post 9 7 [p 12]
      "Ajitama attempt #6 — finally got the jammy centre 🥚✨ 6.5 min, then a 24h soy/mirin bath"
      "" 87 1
      [ Comment 0 "jammy!" "2d", Comment 6 "6.5 is the magic number" "2d" ] "2d"
  , Post 10 2 [p 11, p 5]
      "Chashu bowl, then tantanmen, because balance 🌶"
      "Tenjin, Fukuoka" 1450 3
      [ Comment 4 "the sesame 🔥" "2d" ] "2d"
  , Post 11 1 [p 8]
      "Kitakata: flat curly noodles, light shoyu, morning ramen culture ☀️ #asaramen"
      "Kitakata, Fukushima" 990 5
      [ Comment 0 "morning ramen is undefeated" "3d" ] "3d"
  , Post 12 4 [p 21]
      "Hiroshima tsukemen: cold noodles, spicy dip, a mountain of cabbage 🥬🌶"
      "Hiroshima" 780 2
      [ Comment 6 "cabbage forward, love it" "3d" ] "3d"
  , Post 13 6 [p 16]
      "Kyoto chicken paitan — creamy but light 🐔"
      "Kyoto" 2890 1
      [ Comment 3 "paitan gang" "4d" ] "4d"
  , Post 14 3 [p 20, p 15]
      "Tokushima (raw egg + pork belly) and Wakayama (pork-soy). Regional ramen road trip, pt. 3 🚗"
      "Tokushima" 1330 0
      [ Comment 2 "pt. 4 when" "5d" ] "5d"
  , Post 15 7 [p 18]
      "Taiwan ramen in Nagoya — minced pork, chili, garlic chives 🔥 my new favourite thing"
      "Nagoya" 142 2
      [ Comment 5 "🔥🔥🔥" "1w" ] "1w"
  , Post 16 5 [p 2]
      "Shoyu ramen + sushi + tempura set. Lunch of champions 🍣"
      "Shinjuku, Tokyo" 2011 6
      [ Comment 1 "set meal supremacy" "1w" ] "1w"
  , Post 17 0 [p 10]
      "Instant ramen upgrade: two packets, extra chili, add an egg. Don't @ me 🍜 #jinramen"
      "Home" 1620 3
      [ Comment 4 "no notes" "1w", Comment 7 "the spicy packet is a must" "1w" ] "1w"
  ]
-----------------------------------------------------------------------------
-- | The activity inbox, newest first. The first four are "Today".
notifications :: [Notif]
notifications =
  [ Notif 3 NLiked "2m" (Just (p 12))
  , Notif 1 (NCommented "6.5 is the magic number") "18m" (Just (p 12))
  , Notif 5 NFollowed "1h" Nothing
  , Notif 0 NLiked "3h" (Just (p 18))
  , Notif 6 (NMentioned "@miso_dev you'd love this one") "5h" (Just (p 17))
  , Notif 2 NFollowed "1d" Nothing
  , Notif 4 NLiked "2d" (Just (p 12))
  , Notif 1 NFollowed "3d" Nothing
  , Notif 0 (NCommented "jammy!") "2d" (Just (p 12))
  ]
-----------------------------------------------------------------------------
-- | The explore grid: every photo, in a fixed shuffle so it doesn't mirror
-- the feed.
exploreOrder :: [MisoString]
exploreOrder = map p [14, 3, 21, 1, 9, 17, 0, 12, 7, 5, 16, 22, 10, 2, 19, 8, 13, 4, 20, 6, 11, 15, 18]
-----------------------------------------------------------------------------
-- | The "camera roll" offered when you post — most recent first.
cameraRoll :: [MisoString]
cameraRoll = defaultPick : map p [21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
-----------------------------------------------------------------------------
-- | The photo the picker starts on (the most recent in the roll).
defaultPick :: MisoString
defaultPick = p 22
-----------------------------------------------------------------------------
