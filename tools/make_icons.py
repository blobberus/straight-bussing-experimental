"""Make the web app icons from the owner's icon. Run from the repo root: python tools/make_icons.py (needs Pillow:
pip install pillow).

Source: straight-bussing-icon-LARGE.png at the repo root (owner, 2026-10-15: a white bird on a bus on teal, square,
1000 x 1000). To change the icon, replace that file (square, at least 512 px, opaque) and run this again; the iPhone
app's icon is made from the same file by ios/scripts/make_icon.py on every CI build.

Rounded corners (owner 2026-10-15: "round the corners of the image slightly like an app"): the icons a system shows
as they are get the iPhone's continuous-corner shape (a superellipse, transparent outside): icon-32.png (browser tab),
icon-192.png / icon-512.png (purpose "any": desktop installs) and straight-bussing-icon-rounded.png at the repo root
(full size, for the poster). The ones a system rounds itself stay square and opaque, or the corners would be doubled
or turn black: icon-180.png (iPhone Home Screen), icon-maskable-512.png (Android: the picture at 80% on its own teal,
inside the mask's safe zone) and the App Store icon (Apple wants it square, no transparency). Lanczos resampling.

EXPERIMENTAL COPY (owner 2026-11-04: "Place a yellow border around the site icon so that I know that this site is the
experimental version"): EXPERIMENTAL_BORDER below draws a yellow ring on every web icon, so the test site's tab, Home
Screen and install icons never look like the live app's. Rounded icons: a ring along their squircle edge. icon-180
(iOS rounds it): the same ring, and yellow outside it too, so iOS's own mask can only cut into yellow. Maskable:
the picture a little smaller inside a yellow surround, so every mask shape (circle, squircle, square) shows yellow.
The repo-root poster stays without the ring. Set EXPERIMENTAL_BORDER = None to make the plain icons.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "straight-bussing-icon-LARGE.png")
ROUNDED = os.path.join(ROOT, "straight-bussing-icon-rounded.png")
OUT = os.path.join(ROOT, "web", "icons")
SQUARE = {"icon-180.png": 180}                                     # iOS rounds the Home Screen icon itself
ROUND = {"icon-32.png": 32, "icon-192.png": 192, "icon-512.png": 512}   # shown as drawn
MASKABLE = 0.8   # the maskable safe zone: a circle of 40% radius, the picture fits inside at 80%
SQUIRCLE_N = 5.0  # |x|^n + |y|^n <= 1: close to the iPhone's continuous corners (n = 2 would be a circle)
SS = 4            # supersampling of the corner mask (smooth edges)
EXPERIMENTAL_BORDER = (255, 214, 10)   # Apple system yellow #FFD60A: the experimental site's icon ring (None = off)
BORDER = 0.06                          # ring width as a share of the icon size (2 px on the 32 px tab icon)
MASKABLE_EXP = 0.70                    # maskable picture scale inside the yellow surround


def load(path=SRC):
    from PIL import Image
    im = Image.open(path)
    if im.width != im.height or im.width < 512:
        raise SystemExit(f"{os.path.basename(path)} must be square and at least 512 px (is {im.width} x {im.height})")
    im = im.convert("RGBA")
    bg = Image.new("RGBA", im.size, im.getpixel((0, 0))[:3] + (255,))   # any transparency onto its own corner color
    return Image.alpha_composite(bg, im).convert("RGB")


def render(im, size, scale=1.0):
    from PIL import Image
    if scale >= 1:
        return im.resize((size, size), Image.LANCZOS)
    out = Image.new("RGB", (size, size), im.getpixel((0, 0)))
    inner = round(size * scale)
    out.paste(im.resize((inner, inner), Image.LANCZOS), ((size - inner) // 2, (size - inner) // 2))
    return out


def squircle_mask(size, n=SQUIRCLE_N):
    """An L mask of the app-icon shape, supersampled then reduced (anti-aliased edge)."""
    from PIL import Image
    big = size * SS
    half = (big - 1) / 2
    rows = []
    for y in range(big):
        v = abs((y - half) / half) ** n
        # |x| limit on this row: (1 - |y|^n)^(1/n), as a pixel span around the center
        w = (1 - v) ** (1 / n) * half if v < 1 else -1
        lo, hi = half - w, half + w
        rows.append(bytes(255 if lo <= x <= hi else 0 for x in range(big)))
    return Image.frombytes("L", (big, big), b"".join(rows)).resize((size, size), Image.LANCZOS)


def rounded(im, size):
    out = render(im, size).convert("RGBA")
    out.putalpha(squircle_mask(size))
    return out


def ring_width(size):
    return max(2, round(size * BORDER))


def inner_mask(size):
    """The squircle shrunk by the ring width, centered: the part of the icon that stays the picture."""
    from PIL import Image
    bw = ring_width(size)
    m = Image.new("L", (size, size), 0)
    m.paste(squircle_mask(size - 2 * bw), (bw, bw))
    return m


def with_ring(icon, size, outside=False):
    """Yellow where the icon's squircle is but the inner squircle is not (the ring); with outside=True, yellow also
    outside the squircle (for icons a system rounds itself)."""
    from PIL import Image, ImageChops
    yellow = Image.new("RGBA", (size, size), EXPERIMENTAL_BORDER + (255,))
    keep = inner_mask(size)
    if outside:
        out = yellow.copy()
        out.paste(icon.convert("RGBA"), (0, 0), keep)
        return out.convert("RGB")
    ring = ImageChops.subtract(squircle_mask(size), keep)
    out = icon.convert("RGBA").copy()
    out.paste(yellow, (0, 0), ring)
    return out


def maskable_ring(im, size):
    """The picture at MASKABLE_EXP inside a circle (the safe zone, a bit inside the 40 % radius); yellow around it."""
    from PIL import Image, ImageDraw
    pic = render(im, size, MASKABLE_EXP).convert("RGBA")
    big = size * SS
    m = Image.new("L", (big, big), 0)
    r = 0.37 * big
    ImageDraw.Draw(m).ellipse((big / 2 - r, big / 2 - r, big / 2 + r, big / 2 + r), fill=255)
    m = m.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), EXPERIMENTAL_BORDER + (255,))
    out.paste(pic, (0, 0), m)
    return out.convert("RGB")


def main():
    try:
        import PIL  # noqa: F401
    except ImportError:
        print("Pillow is needed: pip install pillow", file=sys.stderr)
        return 2
    im = load()
    os.makedirs(OUT, exist_ok=True)
    exp = EXPERIMENTAL_BORDER is not None
    for name, size in SQUARE.items():
        icon = render(im, size)
        (with_ring(icon, size, outside=True) if exp else icon).save(os.path.join(OUT, name), "PNG", optimize=True)
    for name, size in ROUND.items():
        icon = rounded(im, size)
        (with_ring(icon, size) if exp else icon).save(os.path.join(OUT, name), "PNG", optimize=True)
    (maskable_ring(im, 512) if exp else render(im, 512, MASKABLE)).save(
        os.path.join(OUT, "icon-maskable-512.png"), "PNG", optimize=True)
    rounded(im, im.width).save(ROUNDED, "PNG", optimize=True)
    print("wrote", ", ".join(list(SQUARE) + list(ROUND) + ["icon-maskable-512.png"]), "in web/icons and",
          os.path.basename(ROUNDED), "from", os.path.basename(SRC))
    return 0


if __name__ == "__main__":
    sys.exit(main())
