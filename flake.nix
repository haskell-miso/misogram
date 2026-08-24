{
  description = "miso-gram — Misogram, an Instagram clone made of ramen, in Haskell (miso-native)";

  inputs = {
    miso.url = "github:dmjio/miso/dual-thread";
  };
  # For local miso development (with uncommitted changes), override the input to
  # a local checkout — note the ABSOLUTE path (relative `path:../miso` doesn't
  # resolve correctly from a git flake):
  #
  #   nix build --override-input miso path:/absolute/path/to/miso

  outputs = inputs:
    let miso = inputs.miso;
    in miso.inputs.flake-utils.lib.eachDefaultSystem (system:
      let
        inherit (miso.inputs.nixpkgs) lib;   # for lib.cleanSource

        # Full nixpkgs, for bun/nodejs (bundle build) and androidenv below —
        # miso's GHC-JS package set (ghcNative) doesn't carry the
        # general-purpose stuff. allowUnfree + accept_license: the Android SDK
        # components are under Google's SDK license, which nixpkgs marks
        # unfree — building/entering the `android` shell is you accepting that
        # license, the same way opening Xcode is for ios/.
        pkgs = import miso.inputs.nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        # miso's GHC-JS (LynxJS) package set, with miso-native — exposed by miso's
        # flake, so we don't re-import nixpkgs + the overlay here.
        ghcNative = miso.lib.${system}.ghcNative;

        # Android SDK/emulator, fetched and managed entirely by Nix (see
        # android/README.md). Powers the `android` devShell and the
        # `android-simulator` app below.
        androidComposition = pkgs.androidenv.composeAndroidPackages {
          platformVersions = [ "34" ];
          buildToolsVersions = [ "34.0.0" ];
          abiVersions = if pkgs.stdenv.hostPlatform.isAarch64
                        then [ "arm64-v8a" ]
                        else [ "x86_64" ];
          includeSystemImages = true;
          systemImageTypes = [ "google_apis" ];
          includeEmulator = true;
          includeNDK = false;
        };

        # The app, compiled with the GHC JavaScript backend against miso's
        # native (-fnative) build.
        miso-gram =
          ghcNative.callCabal2nix "miso-gram" (lib.cleanSource ./.) {
            miso = ghcNative.miso-native;
          };

        # The Lynx bundle. This is miso's shared `mkLynxBundle` helper, forked
        # locally (nix/mk-lynx-bundle.nix) so that JPEG photos are inlined as
        # well as PNGs — 23 ramen photos as PNG would be ~10x the bundle size.
        mkLynxBundle = import ./nix/mk-lynx-bundle.nix {
          inherit pkgs;
          rspeedy = miso.packages.${system}.rspeedy;
        };

        bundle = mkLynxBundle {
          name = "miso-gram-bundle";
          jsDrv = miso-gram;
          exeName = "miso-gram";
          assets = ./assets;
          styles = ./styles.css;
        };
      in
      {
        # `nix build` -> result/main.lynx.bundle
        packages = {
          default = bundle;
          inherit bundle;
          app = miso-gram;
        };

        # Inherit miso's dev shells (toolchain: GHC JS backend, bun, rspeedy),
        # plus an `android` shell for the ios/-equivalent Android host app.
        devShells = {
          default = miso.devShells.${system}.default;
          native = miso.devShells.${system}.native;
          wasm = miso.devShells.${system}.wasm;

          # `nix develop .#android` -> JDK, Gradle, and a Nix-fetched Android
          # SDK on $PATH. See android/README.md for the full build workflow.
          android = pkgs.mkShell {
            packages = [ androidComposition.androidsdk pkgs.jdk17 pkgs.gradle ];
            ANDROID_HOME = "${androidComposition.androidsdk}/libexec/android-sdk";
            ANDROID_SDK_ROOT = "${androidComposition.androidsdk}/libexec/android-sdk";
            # Points Gradle/AGP at the Nix-provided aapt2 instead of trying to
            # fetch its own copy from Maven — see nixpkgs manual §Android.
            GRADLE_OPTS =
              "-Dorg.gradle.project.android.aapt2FromMavenOverride=" +
              "${androidComposition.androidsdk}/libexec/android-sdk/build-tools/34.0.0/aapt2";
          };
        };

        # `nix run .#android-simulator` -> boots a Nix-managed AVD (no APK
        # pre-installed; `adb install` it yourself per android/README.md).
        apps.android-simulator = {
          type = "app";
          program = "${pkgs.androidenv.emulateApp {
            name = "miso-gram-emulator";
            platformVersion = "34";
            abiVersion = if pkgs.stdenv.hostPlatform.isAarch64
                         then "arm64-v8a"
                         else "x86_64";
            systemImageType = "google_apis";
          }}/bin/run-test-emulator";
        };
      });
}
