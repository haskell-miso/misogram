# MisoGram — Android host app

A minimal native Android app that renders the miso-gram `main.lynx.bundle` on
an emulator or device. It follows the official
[Lynx Android integration guide](https://lynxjs.org/guide/start/integrate-with-existing-apps?platform=android)
and mirrors [`../ios/App/`](../ios/App) file-for-file (`MisoGramApplication` ~
`AppDelegate.m`, `TemplateProvider`, `MainActivity` ~ `ViewController.m`), so
the two host apps stay easy to compare. It is the `miso-lynx-gallery` host app
with a new package name, a launcher icon (`res/mipmap-*`, adaptive on API 26+)
and a launch screen (`SplashTheme` + `res/drawable/splash.xml`, the gradient
bowl glyph on white — the same artwork as the iOS `LaunchLogo`).

Unlike Xcode, the Android SDK/emulator are redistributable, so `nix develop
.#android` fetches the whole Android toolchain through Nix itself (see
`flake.nix`'s `androidComposition`).

## Steps

**1. Build the Lynx bundle** (repo root):

```bash
nix build                    # -> result/main.lynx.bundle
```

**2. Copy the bundle into this app's assets:**

```bash
cp result/main.lynx.bundle android/app/src/main/assets/main.lynx.bundle
```

**3. Build the APK, from the Nix-provided Android dev shell:**

```bash
nix develop .#android
cd android
gradle assembleDebug        # -> app/build/outputs/apk/debug/app-debug.apk
```

**4. Boot the Nix-managed emulator and install the APK:**

```bash
nix run .#android-simulator   # boots an AVD via androidenv.emulateApp
# in another terminal, once it's booted:
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n io.dmj.misogram/.MainActivity
```

## Iterating

- **Re-embed after a code change:** rebuild the bundle, re-copy it into
  `assets/`, then `gradle installDebug`.
- **Load from a dev server instead of embedding** (faster loop, no rebuild of
  the app): serve `result/` over HTTP, then change `TEMPLATE_URL` in
  `MainActivity.java` to `http://<your-host-ip>:8080/main.lynx.bundle`
  (`usesCleartextTraffic` is already enabled in `AndroidManifest.xml`).

## Notes / caveats

- **Untested**, like the gallery's: the Java is adapted from the official Lynx
  Android integration guide, not run on a device/emulator by the author.
- `org.lynxsdk.lynx:xelement` is required: the search bar, the comment box and
  the caption editor are `<input>` / `<textarea>` XElements
  (`XElementBehaviors` is registered in `MainActivity`).
- **Not hermetic.** `gradle` still resolves `org.lynxsdk.lynx:*` and friends
  from Maven Central over the network; `nix develop .#android` gives you the
  SDK/JDK/Gradle toolchain, not a pure `nix build` of the APK.
