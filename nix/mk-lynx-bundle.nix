# mkLynxBundle — build a Lynx `.lynx.bundle` from a GHC-JS-backend app.
#
# A local fork of miso's `nix/lib/mk-lynx-bundle.nix` (the helper exposed as
# `miso.lib.${system}.mkLynxBundle`). Given the app's ghcjs derivation (whose
# `bin/<exe>.jsexe/all.js` is the compiled program), plus an optional
# stylesheet and assets directory, it minifies all.js, wires up a small rspeedy
# entry, and runs `rspeedy build`.
#
# The one difference from upstream: every PNG *and JPEG* under `assets` is
# `import`ed with `?inline`, so rspeedy embeds it as a `data:` URI in the
# bundle (offline, no asset server) and registers it by relative name on
# `globalThis.__misoGramAssets` for Haskell to read back (see
# src/MisoGram/Assets.hs). Upstream only inlines PNGs; photos as PNG would be
# ~10x larger than as JPEG, which matters at 23 photos.
#
# `styles.css` is compiled into the bundle under the global cssId 0 (Lynx
# compiles CSS ahead of time; runtime injection doesn't work).
{ pkgs, rspeedy }:

{ name ? "lynx-bundle"
, jsDrv                    # the app's ghcjs derivation
, exeName                  # executable name; its `.jsexe/all.js` is the program
, assets ? null            # optional path to a directory of PNG/JPEG files to inline
, styles ? null            # optional path to a styles.css to compile in
, registry ? "__misoGramAssets"   # global the asset table is registered on
}:

with pkgs.lib;

let
  entryJs = pkgs.writeText "entry.js" (
    optionalString (assets != null) "import './__assets.js';\n"
    + optionalString (styles != null) "import './styles.css';\n"
    + "import './all.js';\n"
  );

  lynxConfig = pkgs.writeText "lynx.config.ts" ''
    import { defineConfig } from '@lynx-js/rspeedy';
    import { pluginReactLynx } from '@lynx-js/react-rsbuild-plugin';
    export default defineConfig({
      source: { entry: './entry.js' },
      plugins: [ pluginReactLynx() ],
    });
  '';
in
pkgs.stdenv.mkDerivation {
  inherit name;
  phases = [ "buildPhase" "installPhase" ];
  nativeBuildInputs = [ pkgs.bun rspeedy pkgs.nodejs ];

  buildPhase = ''
    export HOME=$TMPDIR
    mkdir -p build

    # Pre-bundle all.js so rspeedy doesn't choke on the GHC JS RTS's Node shims.
    ${pkgs.bun}/bin/bun build \
      --minify-whitespace \
      --target=bun \
      --outfile=build/all.js \
      ${jsDrv}/bin/${exeName}.jsexe/all.js

    ln -s ${rspeedy}/lib/node_modules build/node_modules
    cp ${lynxConfig} build/lynx.config.ts
    cp ${entryJs} build/entry.js
    ${optionalString (styles != null) "cp ${styles} build/styles.css"}
    ${optionalString (assets != null) ''
      cp -r ${assets} build/assets
      chmod -R u+w build/assets
      (
        cd build
        echo "const reg = {};"
        n=0
        for f in $(find assets -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' \) | sort); do
          key="''${f#assets/}"
          echo "import a$n from './$f?inline';"
          echo "reg['$key'] = a$n;"
          n=$((n + 1))
        done
        echo "globalThis.${registry} = reg;"
      ) > build/__assets.js
    ''}

    cd build
    ${rspeedy}/bin/rspeedy build
  '';

  installPhase = ''
    mkdir -p $out
    cp -r dist/. $out/
  '';
}
