#!/usr/bin/env python3
# Regenerates every PNG under assets/icons/ (and the two white brand marks)
# from the SVG paths below: 24x24 viewBox glyphs rasterised to 96x96 RGBA with
# a transparent background, one file per colour variant. Run from the repo
# root:
#
#   nix-shell -p librsvg python3Packages.pillow --run 'python3 nix/gen-icons.py'
#
# The committed PNGs are the build input (nix/mk-lynx-bundle.nix inlines them
# into the bundle); this script only needs re-running when a glyph changes.
import subprocess, os, math

C = {
    "default": "#262626",
    "gray":    "#8e8e8e",
    "white":   "#ffffff",
    "blue":    "#0095f6",
    "red":     "#ed4956",
}
SW = 1.8          # stroke width all outline glyphs share (24-unit viewBox)

# ---------------------------------------------------------------------------
# Glyphs. "stroke" entries are painted stroke-only (round caps/joins,
# fill none); "fill" entries are painted fill-only (fill-rule evenodd, so a
# second subpath cuts a transparent hole — reels-fill's play triangle,
# verified's check).
# ---------------------------------------------------------------------------

HEART = ("M12 20.5 C6.5 16.5 3 13 3 9.3 C3 6.4 5.2 4.2 8 4.2 "
         "C9.7 4.2 11.2 5 12 6.3 C12.8 5 14.3 4.2 16 4.2 "
         "C18.8 4.2 21 6.4 21 9.3 C21 13 17.5 16.5 12 20.5 Z")

HOUSE = "M3.5 10.5 L12 3.3 L20.5 10.5 L20.5 20.2 A0.8 0.8 0 0 1 19.7 21 L4.3 21 A0.8 0.8 0 0 1 3.5 20.2 Z"
DOOR  = "M9.7 21 L9.7 14.6 L14.3 14.6 L14.3 21"

PLANE = ("M21.2 2.8 L3.2 10.3 L10.4 13.6 L21.2 2.8 Z "
         "M21.2 2.8 L13.7 20.8 L10.4 13.6")

BUBBLE = ("M12 3.2 C7 3.2 3.2 6.8 3.2 11.3 C3.2 13.8 4.4 16 6.3 17.5 "
          "L6.3 20.8 L9.4 19.1 C10.2 19.3 11.1 19.4 12 19.4 "
          "C17 19.4 20.8 15.8 20.8 11.3 C20.8 6.8 17 3.2 12 3.2 Z")

BOOKMARK = ("M6 3.5 L18 3.5 A0.8 0.8 0 0 1 18.8 4.3 L18.8 20.8 "
            "L12 16.2 L5.2 20.8 L5.2 4.3 A0.8 0.8 0 0 1 6 3.5 Z")

REELS_RECT = "M7.5 3.5 L16.5 3.5 A4 4 0 0 1 20.5 7.5 L20.5 16.5 A4 4 0 0 1 16.5 20.5 L7.5 20.5 A4 4 0 0 1 3.5 16.5 L3.5 7.5 A4 4 0 0 1 7.5 3.5 Z"
PLAY_TRI   = "M10.4 11.2 L15.2 14.05 L10.4 16.9 Z"

def seal_path():
    # 16-point rosette for the verified badge
    pts = []
    for i in range(16):
        a = math.pi * 2 * i / 16 - math.pi / 2
        r = 9.6 if i % 2 == 0 else 8.0
        pts.append((12 + r * math.cos(a), 12 + r * math.sin(a)))
    return ("M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in pts) + " Z"
            # the check, as a closed band (evenodd hole)
            + " M6.9 12.9 L10.6 16.6 L17.9 9.9 L16.3 8.3 L10.6 13.5 L8.5 11.3 Z")

def sun_rays():
    seg = []
    for i in range(8):
        a = math.pi * 2 * i / 8
        seg.append(f"M{12 + 6.4 * math.cos(a):.2f} {12 + 6.4 * math.sin(a):.2f} "
                   f"L{12 + 8.6 * math.cos(a):.2f} {12 + 8.6 * math.sin(a):.2f}")
    return " ".join(seg)

GLYPHS = {
    # name: (mode, svg-inner-template; {c}=colour, {sw}=stroke width)
    "heart":        ("stroke", f'<path d="{HEART}"/>'),
    "heart-fill":   ("fill",   f'<path d="{HEART}"/>'),
    "home":         ("stroke", f'<path d="{HOUSE}"/><path d="{DOOR}"/>'),
    "home-fill":    ("fill",   f'<path fill-rule="evenodd" d="{HOUSE} M9.7 21 L9.7 14.6 A1.1 1.1 0 0 1 10.8 13.5 L13.2 13.5 A1.1 1.1 0 0 1 14.3 14.6 L14.3 21 Z"/>'),
    "search":       ("stroke", '<circle cx="10.5" cy="10.5" r="6.7"/><path d="M15.4 15.4 L20.3 20.3"/>'),
    "search-fill":  ("stroke2", '<circle cx="10.5" cy="10.5" r="6.7"/><path d="M15.4 15.4 L20.3 20.3"/>'),
    "plus":         ("stroke", '<path d="M12 5 L12 19 M5 12 L19 12"/>'),
    "add-circle":   ("stroke", '<circle cx="12" cy="12" r="8.8"/><path d="M12 8 L12 16 M8 12 L16 12"/>'),
    "back":         ("stroke", '<path d="M15 4 L7 12 L15 20"/>'),
    "chevron-down": ("stroke", '<path d="M6 9.5 L12 15.5 L18 9.5"/>'),
    "close":        ("stroke", '<path d="M5.5 5.5 L18.5 18.5 M18.5 5.5 L5.5 18.5"/>'),
    "menu":         ("stroke", '<path d="M4 6.5 L20 6.5 M4 12 L20 12 M4 17.5 L20 17.5"/>'),
    "more":         ("fill",   '<circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/>'),
    "more-v":       ("fill",   '<circle cx="12" cy="5" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="12" cy="19" r="1.7"/>'),
    "comment":      ("stroke", '<path d="M12 3.2 A8.8 8.8 0 1 1 7.7 19.7 L3.3 20.7 L4.4 16.5 A8.8 8.8 0 0 1 12 3.2 Z"/>'),
    "send":         ("stroke", f'<path d="{PLANE}"/>'),
    "share":        ("stroke", f'<path d="{PLANE}"/>'),
    "messenger":    ("stroke", f'<path d="{BUBBLE}"/><path d="M6.9 13.3 L11 9 L13.2 11.1 L17 8.9"/>'),
    "camera":       ("stroke", '<path d="M5.5 6.5 L18.5 6.5 A2.5 2.5 0 0 1 21 9 L21 17.5 A2.5 2.5 0 0 1 18.5 20 L5.5 20 A2.5 2.5 0 0 1 3 17.5 L3 9 A2.5 2.5 0 0 1 5.5 6.5 Z"/><path d="M8.2 6.5 L9.4 4.2 L14.6 4.2 L15.8 6.5"/><circle cx="12" cy="13.2" r="3.8"/>'),
    "grid":         ("stroke", '<rect x="3.5" y="3.5" width="17" height="17" rx="2"/><path d="M9.17 3.5 L9.17 20.5 M14.83 3.5 L14.83 20.5 M3.5 9.17 L20.5 9.17 M3.5 14.83 L20.5 14.83"/>'),
    "reels":        ("stroke", f'<path d="{REELS_RECT}"/><path d="M3.5 8.3 L20.5 8.3 M8.6 3.5 L11.2 8.3 M14.4 3.5 L17 8.3"/><path d="{PLAY_TRI}"/>'),
    "reels-fill":   ("fill",   f'<path fill-rule="evenodd" d="{REELS_RECT} {PLAY_TRI}"/>'),
    "music":        ("stroke", '<path d="M9.6 18.2 L9.6 6.3 L19.1 4.3 L19.1 16.6"/><circle class="f" cx="7" cy="18.2" r="2.6"/><circle class="f" cx="16.5" cy="16.6" r="2.6"/>'),
    "profile":      ("stroke", '<circle cx="12" cy="8" r="4.2"/><path d="M4.5 20.5 C4.5 16.4 7.9 13.9 12 13.9 C16.1 13.9 19.5 16.4 19.5 20.5"/>'),
    "tagged":       ("stroke", '<rect x="3.5" y="3.5" width="17" height="17" rx="2.5"/><circle cx="12" cy="10" r="2.6"/><path d="M7.5 17.5 C7.5 14.9 9.5 13.4 12 13.4 C14.5 13.4 16.5 14.9 16.5 17.5"/>'),
    "location":     ("stroke", '<path d="M12 21.5 C7.3 16.6 5 13.2 5 10 A7 7 0 0 1 19 10 C19 13.2 16.7 16.6 12 21.5 Z"/><circle cx="12" cy="10" r="2.5"/>'),
    "sun":          ("stroke", f'<circle cx="12" cy="12" r="4.2"/><path d="{sun_rays()}"/>'),
    "check":        ("stroke", '<circle cx="12" cy="12" r="8.8"/><path d="M7.8 12.3 L10.7 15.2 L16.3 9.6"/>'),
    "bookmark":     ("stroke", f'<path d="{BOOKMARK}"/>'),
    "bookmark-fill":("fill",   f'<path d="{BOOKMARK}"/>'),
    "verified":     ("fill",   f'<path fill-rule="evenodd" d="{seal_path()}"/>'),
}

# Every committed icon file: base glyph x colour variants ("" = default).
VARIANTS = {
    "add-circle": ["", "blue", "gray", "white"],
    "verified":   ["", "blue", "gray", "white"],
    "heart":      ["", "gray", "white", "red"],
}
THREE = ["", "gray", "white"]
for g in GLYPHS:
    VARIANTS.setdefault(g, THREE)

def svg(mode, inner, colour):
    sw = 2.6 if mode == "stroke2" else SW
    if mode == "fill":
        paint = f'fill="{colour}" stroke="none"'
    else:
        paint = f'fill="none" stroke="{colour}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"'
    # class="f" opts an element into fill paint inside a stroke glyph (music's note heads)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" {paint}>'
            f'<style>.f{{fill:{colour};stroke:none}}</style>{inner}</svg>')

def render(svg_text, out, size):
    p = subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), "-o", out],
                       input=svg_text.encode(), capture_output=True)
    if p.returncode != 0:
        raise SystemExit(f"{out}: {p.stderr.decode()}")

def main():
    os.makedirs("assets/icons", exist_ok=True)
    n = 0
    for glyph, variants in VARIANTS.items():
        mode, inner = GLYPHS[glyph]
        for v in variants:
            name = glyph + (f"-{v}" if v else "")
            render(svg(mode, inner, C[v or "default"]), f"assets/icons/{name}.png", 96)
            n += 1
    # the big double-tap heart is the filled heart in like-red
    render(svg("fill", GLYPHS["heart-fill"][1], C["red"]), "assets/icons/heart-red-big.png", 96)
    n += 1

    # Brand: the white wireframe bowl glyph (bowl + chopsticks + steam) ...
    bowl = ('<path d="M3.5 11 L20.5 11 A0.4 0.4 0 0 1 20.9 11.45 '
            'C20.5 15.4 17.7 18.2 14.6 19 L14.6 20.2 L9.4 20.2 L9.4 19 '
            'C6.3 18.2 3.5 15.4 3.1 11.45 A0.4 0.4 0 0 1 3.5 11 Z"/>'
            '<path d="M4.5 8.7 L21.5 3.4 M4.5 6.5 L19 2.2"/>'
            '<path d="M8.6 8.2 C8 7.2 8.6 6.6 8.6 5.7 M12 8.2 C11.4 7.2 12 6.6 12 5.7 M15.4 8.2 C14.8 7.2 15.4 6.6 15.4 5.7"/>')
    render(svg("stroke", bowl, C["white"]), "assets/brand/glyph-white.png", 512)
    n += 1

    # ... the same bowl as the Android adaptive-icon foreground: transparent,
    # glyph filling 60% of the canvas (the adaptive safe zone is 66/108dp),
    # one PNG per density of the 108dp base.
    for dpi, size in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216),
                      ("xxhdpi", 324), ("xxxhdpi", 432)]:
        out = f"android/app/src/main/res/mipmap-{dpi}/ic_launcher_foreground.png"
        pad = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="-8 -8 40 40" '
               f'fill="none" stroke="{C["white"]}" stroke-width="{SW}" '
               'stroke-linecap="round" stroke-linejoin="round">'
               f'<style>.f{{fill:{C["white"]};stroke:none}}</style>{bowl}</svg>')
        render(pad, out, size)
        n += 1

    # ... and the white wordmark, recovered from the flattened dark one by
    # turning luminance into alpha (the dark glyph is intact in wordmark.png).
    from PIL import Image
    wm = Image.open("assets/brand/wordmark.png").convert("L")
    white = Image.new("RGBA", wm.size, (255, 255, 255, 0))
    white.putalpha(wm.point(lambda g: 255 - g))
    white.save("assets/brand/wordmark-white.png")
    n += 1
    print(f"wrote {n} PNGs")

if __name__ == "__main__":
    main()
