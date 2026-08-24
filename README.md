# 🍜 📱 miso-gram

**Misogram** — an Instagram clone made entirely of ramen, written in Haskell on
[miso](https://github.com/dmjio/miso)'s **native (LynxJS dual-thread)**
backend. Same idea as [miso-lynx-gallery](https://github.com/haskell-miso/miso-lynx-gallery),
much more app: a splash screen, a home feed with stories and swipeable photo
carousels, explore, reels, profiles, comments, notifications and a "new post"
flow — populated with eight fake accounts (one of them you), seventeen posts,
and twenty-three different bowls of ramen.

<p align="center"><em>Instagram's chrome, pixel for pixel where it counts — but the logo is a white wireframe bowl.</em></p>

## What's in the app

| Screen | What it does |
| --- | --- |
| **Splash** | The gradient bowl glyph on white, "from miso" at the bottom, then the feed (1.6 s). The iOS and Android hosts show the same artwork as their native launch screens. |
| **Home** | Wordmark header (notifications with an unread dot, DMs), a stories bar with gradient rings, and the feed: avatar/username/location header, square photo, heart · comment · send · bookmark, "Liked by … and N others", caption, "View all N comments", "2 hours ago". Multi-photo posts are **swipeable carousels** with a `1/3` counter and dots. **Double-tap** a photo to like it (big white heart pop); tap the heart to like/unlike (it springs). |
| **Search** | Search bar + 3-column explore grid. Typing filters accounts (handle / name) and posts (caption / author). Tap a tile to open the viewer. |
| **Create (+)** | Pick a photo from the "camera roll" (preview + 4-column grid), **Next**, write a caption, **Share**. The post lands at the top of the feed and in your profile grid, with a toast. |
| **Reels** | Full-screen, black, **vertical swipe** between everyone's pictures, with the like/comment/share rail, author + Follow pill, caption and "Original audio" line. |
| **Profile** | Yours and everyone else's: avatar (story ring for others), posts / followers / following, name + bio, Edit/Share profile or **Follow** / Message (following bumps the follower count), story highlights, grid / reels / tagged tabs, and the photo grid. |
| **Viewer** | Tap any grid tile: a black full-screen **horizontal swiper** across that person's (or explore's) pictures, opened on the one you tapped, with a `3 / 12` counter, actions, likes and caption. |
| **Comments** | The caption as the first row, then comments (Reply, ♡), and a comment box that posts as you. |
| **Notifications** | "Today" / "This week": likes and comments with the photo thumbnail, follows with a Follow / Following button. |

Everything is fake and local: no network, no accounts. The photos are
CC-licensed Wikimedia Commons uploads (`assets/photos/CREDITS.json`); the
people are invented.

## Build

Just [Nix](https://nixos.org) (flakes enabled) — the flake pulls miso (the
`dual-thread` branch) and its toolchain, so you don't need anything else:

```bash
nix build           # -> result/main.lynx.bundle
```

Serve it and point a Lynx host at the bundle:

```bash
nix develop -c http-server result -p 8080
# then open LynxExplorer at  http://<your-machine-ip>:8080/main.lynx.bundle
```

(Any static file server works — e.g. `python3 -m http.server 8080 -d result`.)
The bundle needs Lynx's **XElements** in the host (`<input>` / `<textarea>` for
the search bar, comment box and caption editor) — LynxExplorer has them, and so
do the host apps in `ios/` and `android/` (see their READMEs for the app icon,
launch screen, and the build steps).

To typecheck on plain GHC without the JS toolchain, `cabal build` against the
miso rev pinned in `cabal.project` (it builds miso with `+native`; the
`Miso.Native.*` modules compile on vanilla GHC).

## How it's built

```
src/Main.hs               entry point, Model/Action, update (BTS), navigation
src/MisoGram/Types.hs     User / Post / Comment / Notif, Screen / Tab, Model, Action
src/MisoGram/Data.hs      the fake social graph: accounts, posts, comments, inbox
src/MisoGram/View.hs      every screen, in Lynx's native elements
src/MisoGram/Swiper.hs    the main-thread swiper behind carousels / viewer / reels
src/MisoGram/Assets.hs    the bundled-asset registry
styles.css                the class rules (Instagram's palette and metrics)
assets/                   photos/, avatars/, icons/, brand/
nix/mk-lynx-bundle.nix    miso's bundle helper, forked to inline JPEGs too
```

- **One root component, screens as data.** The `Model` is the navigation state
  (a current `Screen` over a back stack, plus the selected `Tab`), the feed, and
  everything you can toggle or type; `updateModel` is the app and runs on the
  background thread (BTS). Native `className` resolves one token per node, so
  every visual state is its own class in `styles.css`.
- **Dual-thread by construction.** The only main-thread (MTS) work is the
  swiper (`MisoGram.Swiper`): the `product-detail` swiper from
  miso-lynx-gallery (itself a port of `lynx-examples/examples/swiper`),
  generalised to *many tracks* and *either axis*. Its touch handlers are
  `*MainWith` events wrapped in `event . static`, drag state lives in one
  `MainThreadRef`, `touchmove` only records where the finger wants the track and
  a vsync-coalesced `eachFrame` loop paints it once per frame, and the snap on
  release is a native compositor transition. A track describes itself through
  attributes (`data-key`, `data-n`, `data-axis`, `data-size`, `data-start`) that the
  MTS reads with `getAttribute` when the finger lands, so one global ref serves
  every carousel on screen. The two threads are bridged explicitly: a settled
  page crosses MTS→BTS as `Snapped` → `SetPage` via `runOnBG` (repainting the
  dots / counter), and every navigation crosses BTS→MTS as `ResetSwipers` via
  `runOnMain`, because freshly created tracks sit at page 0 again.
- **Double tap** is two `tap`s on the same photo within 350 ms, stamped with
  `Date.now()` on the BTS; the big heart is a CSS transition between two classes.
- **Images.** rspeedy never sees the `src` strings the GHC JS backend emits, so
  `nix/mk-lynx-bundle.nix` `import`s every PNG *and JPEG* under `assets/` with
  `?inline` and registers the resulting `data:` URIs on
  `globalThis.__misoGramAssets`; `MisoGram.Assets.asset` reads them back. (miso's
  own `mkLynxBundle` only inlines PNGs; the 23 photos as PNG would be ~10× the
  size.) The line icons are rendered from hand-drawn SVG paths at 96 px in every
  colour the UI needs; the app icon, launch logo and wordmark live in
  `assets/brand/` and the host apps' asset catalogs.

## Credit

The ramen photos are Wikimedia Commons uploads under CC0 / CC BY / CC BY-SA
(per-file attribution in `assets/photos/CREDITS.json`). Instagram's design is
Meta's; this is a from-scratch look-alike for fun, with a bowl where the camera
used to be.
