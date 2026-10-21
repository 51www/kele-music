# -*- coding: utf-8 -*-
"""Generate Android launcher icons: dark gradient bg + golden music note.

Outputs:
  - legacy square mipmap-*/ic_launcher.png (48/72/96/144/192)
  - adaptive icon: mipmap-*/ic_launcher_foreground.png (108/162/216/324/432)
    + values/ic_launcher_background.xml color
    + mipmap-anydpi-v26/ic_launcher.xml
"""
import os
from PIL import Image, ImageDraw

S = 1024
OUT = r"E:\www\netease-music\android\app\src\main\res"
GOLD = (255, 200, 115)

def vgrad(size, top, bot):
    """Opaque vertical-gradient RGB image."""
    img = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,)
        d.line([(0, y), (size, y)], fill=c)
    return img

def note_layer(size, scale=1.0, cx=0.5, cy=0.5):
    """Transparent layer with golden beamed note, scaled about its center."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # draw note at 1024 reference coords then scale the whole stamp
    ref = 1024
    stamp = Image.new("RGBA", (ref, ref), (0, 0, 0, 0))
    sd = ImageDraw.Draw(stamp)

    def head(x, y, w=150, h=110, angle=-20):
        himg = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        hd = ImageDraw.Draw(himg)
        hd.ellipse([0, 0, w - 1, h - 1], fill=GOLD + (255,))
        himg = himg.rotate(angle, expand=True, resample=Image.BICUBIC)
        stamp.alpha_composite(himg, (int(x - himg.width / 2), int(y - himg.height / 2)))

    head(330, 760)
    head(660, 690)
    sd.polygon([(395, 380), (428, 380), (428, 748), (395, 742)], fill=GOLD + (255,))
    sd.polygon([(722, 318), (755, 318), (755, 678), (722, 672)], fill=GOLD + (255,))
    sd.polygon([(395, 378), (755, 316), (755, 402), (395, 464)], fill=GOLD + (255,))

    if scale != 1.0:
        ns = int(ref * scale)
        stamp = stamp.resize((ns, ns), Image.LANCZOS)
    ox = int(size * cx - stamp.width / 2)
    oy = int(size * cy - stamp.height / 2)
    layer.alpha_composite(stamp, (ox, oy))
    return layer

def glow_layer(size, center, max_rad, peak=70):
    """Soft radial glow, correctly alpha-composited."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(layer)
    cx, cy = center
    for r in range(max_rad, 0, -6):
        t = 1 - r / max_rad
        a = int(peak * t * t)
        gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=GOLD + (a,))
    return layer

def grooves_layer(size, center, r0, r1, step, alpha=26):
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(layer)
    cx, cy = center
    for rad in range(r0, r1, step):
        gd.ellipse([cx - rad, cy - rad, cx + rad, cy + rad],
                   outline=(255, 255, 255, alpha), width=3)
    return layer

# ---------- legacy square icons ----------
top, bot = (24, 26, 48), (58, 36, 78)
master = vgrad(S, top, bot)
master.alpha_composite(grooves_layer(S, (int(S*0.30), int(S*0.26)), 150, 470, 46))
master.alpha_composite(glow_layer(S, (int(S*0.62), int(S*0.55)), 300, peak=55))
master.alpha_composite(note_layer(S))
master.save(r"E:\www\netease-music\docs\screenshots\app_icon_master.png")

legacy = {"mipmap-mdpi": 48, "mipmap-hdpi": 72, "mipmap-xhdpi": 96,
          "mipmap-xxhdpi": 144, "mipmap-xxxhdpi": 192}
for folder, size in legacy.items():
    master.resize((size, size), Image.LANCZOS).save(
        os.path.join(OUT, folder, "ic_launcher.png"), "PNG")

# ---------- adaptive icon foreground (108dp, safe zone 66dp center) ----------
fg_master = Image.new("RGBA", (S, S), (0, 0, 0, 0))
fg_master.alpha_composite(glow_layer(S, (int(S*0.60), int(S*0.56)), 260, peak=45))
fg_master.alpha_composite(note_layer(S, scale=0.56))
fg_master.save(r"E:\www\netease-music\docs\screenshots\app_icon_foreground_master.png")

fg_sizes = {"mipmap-mdpi": 108, "mipmap-hdpi": 162, "mipmap-xhdpi": 216,
            "mipmap-xxhdpi": 324, "mipmap-xxxhdpi": 432}
for folder, size in fg_sizes.items():
    fg_master.resize((size, size), Image.LANCZOS).save(
        os.path.join(OUT, folder, "ic_launcher_foreground.png"), "PNG")

# ---------- adaptive icon xml + background color ----------
v26 = os.path.join(OUT, "mipmap-anydpi-v26")
os.makedirs(v26, exist_ok=True)
with open(os.path.join(v26, "ic_launcher.xml"), "w", encoding="utf-8") as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '</adaptive-icon>\n')

# gradient approximated by solid dusk color used behind foreground
with open(os.path.join(OUT, "values", "ic_launcher_background.xml"), "w",
          encoding="utf-8") as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources>\n'
            '    <color name="ic_launcher_background">#24223F</color>\n'
            '</resources>\n')

print("done: legacy + adaptive icons written")
