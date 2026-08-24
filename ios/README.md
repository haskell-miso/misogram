# MisoGram — iOS host app

A minimal native iOS app that renders the miso-gram `main.lynx.bundle` on an
iPhone: a plain `UIWindow` + `UIViewController` hosting a `LynxView`, mirroring
the official [Lynx iOS integration](https://lynxjs.org/guide/start/integrate-with-existing-apps.html)
and the LynxExplorer's `TemplateProvider`. It is the `miso-lynx-gallery` host
app with a new name, the Misogram app icon, and an Instagram-style launch
screen (the gradient bowl glyph on white — `LaunchLogo` /
`LaunchBackgroundColor` in `Assets.xcassets`, wired up via `UILaunchScreen`
in `Info.plist`).

## Prerequisites (macOS)

```bash
brew install xcodegen cocoapods   # Xcode 15+ also required
```

## Steps

**1. Build the Lynx bundle** (repo root):

```bash
nix build                        # -> result/main.lynx.bundle
```

**2. Copy the bundle into this app's resources:**

```bash
cp result/main.lynx.bundle ios/Resource/main.lynx.bundle
```

**3. Generate the Xcode project and install pods** (from this `ios/` dir):

```bash
cd ios
xcodegen generate            # -> MisoGram.xcodeproj
pod install                  # -> MisoGram.xcworkspace
```

**4. Open, sign, run:**

```bash
open MisoGram.xcworkspace     # NOT the .xcodeproj
```

- In Xcode: **Signing & Capabilities** → select your **Personal Team** (Apple ID)
  and set a unique **Bundle Identifier** (e.g. `com.<you>.MisoGram`), enable
  *Automatically manage signing*.
- Select your iPhone (or a simulator) as the run destination, press **⌘R**.
- First run on a device: **Settings → General → VPN & Device Management** →
  trust your developer profile.

You should see the native launch screen (gradient bowl on white), then
Misogram's own splash, then the feed.

## Iterating

- **Re-embed after a code change:** `nix build && cp result/main.lynx.bundle
  ios/Resource/`, then re-run in Xcode.
- **Load from a dev server instead of embedding** (faster loop, no rebuild of the
  app): serve `result/` over HTTP, then set `kTemplateURL` in
  `App/ViewController.m` to `http://<your-mac-ip>:8080/main.lynx.bundle`. (ATS
  arbitrary loads is already enabled in `Info.plist` for local HTTP.)

## Notes / caveats

- The `XElement` pod is required: the search bar, the comment box and the
  caption editor are `<input>` / `<textarea>` XElements. The `-ObjC` linker flag
  in the `Podfile` keeps their registrations alive on device builds.
- Uses `LynxThreadStrategyForRenderAllOnUI` (the explorer default the gallery
  bundle was verified under). If rendering misbehaves, that's the first knob.
- Regenerated files (`*.xcodeproj`, `*.xcworkspace`, `Pods/`, the copied bundle)
  are git-ignored; `project.yml`, `Podfile`, and `App/` sources are the source of
  truth.
