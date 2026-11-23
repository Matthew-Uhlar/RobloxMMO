"""Approximate offline previews of §28 v2 floating signs (Pillow; not Roblox captures).

    lune run tools/dump-signs.luau build/signs.json "Artisans' Row" "Starforge" ...
    python3 tools/render-signs.py build/signs.json docs/screenshots/signs-v2-day.png [--night] [--nameplate]

Each sign's BillboardGui tree (CanvasGroup root at UIScale 1) is painted the
way Roblox draws it: rounded frames (UICorner), two-stop UIGradients, UIStroke
borders and text outlines, rotated frames (diamonds, post arrows about their
holder), RichText small caps and colour emoji crests. Each cell shows the
plaque floating over an island backdrop with its ground anchor. --night dims
the backdrop, keeps the self-lit plaque (LightInfluence 0.15) and uses each
crystal glow's NightTransparency. --nameplate adds an NPC nameplate cell for
comparison. Fonts are stand-ins (DejaVu Serif Bold at 92% for Merriweather Bold,
Caladea Bold Italic for Fondamento, Inter Bold for BuilderSans): glyphs
are wider than Roblox's, so text that fits here fits in Studio.
"""
import json
import math
import re
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SERIF = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
SERIF_ITALIC = "/usr/share/fonts/truetype/crosextra/Caladea-BoldItalic.ttf"
SANS = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"
EMOJI = "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf"
CELL_W, CELL_H, K = 560, 380, 2  # cell size and supersampling
EMOJI_RE = re.compile("[\U0001F000-\U0001FAFF☀-➿️⬀-⯿]")


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def font_for(family, size):
    path = SANS if "BuilderSans" in family else (SERIF_ITALIC if "Fondamento" in family else SERIF)
    # DejaVu Serif Bold is wider than Merriweather Bold (calibrated as in v1).
    k = 1 if "BuilderSans" in family else .92
    return ImageFont.truetype(path, max(4, int(size * k)))


def radius_of(it):
    if not it.get("corner"):
        return 0
    scale, offset = it["corner"]
    return min(it["w"], it["h"]) / 2 if scale >= 1 else offset


def gradient_fill(w, h, c0, c1):
    img = Image.new("RGB", (max(1, w), max(1, h)))
    d = ImageDraw.Draw(img)
    for row in range(max(1, h)):
        t = row / max(1, h - 1)
        d.line([(0, row), (w, row)], fill=tuple(int(c0[i] * (1 - t) + c1[i] * t) for i in range(3)))
    return img


def runs_of(it):
    """[(text, size)] runs for a label (RichText <font size> spans)."""
    text, size = it["text"], it["size"]
    if not it.get("rich"):
        return [(text, size)]
    out, pos = [], 0
    for m in re.finditer(r'<font size="(\d+)">(.*?)</font>', text):
        if m.start() > pos:
            out.append((text[pos:m.start()], size))
        out.append((m.group(2), int(m.group(1))))
        pos = m.end()
    if pos < len(text):
        out.append((text[pos:], size))
    return [(t.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">"), s) for t, s in out]


def draw_text(layer, it, s, night):
    runs = runs_of(it)
    family = it["font"]
    # Split runs into words (a word may span runs: small caps).
    words, cur = [], []
    for t, size in runs:
        parts = re.split(r"(\s+)", t)
        for p in parts:
            if p == "":
                continue
            if p.isspace():
                if cur:
                    words.append(cur)
                    cur = []
            else:
                cur.append((p, size))
    if cur:
        words.append(cur)
    probe = ImageDraw.Draw(layer)

    def wlen(word):
        return sum(probe.textlength(t, font=font_for(family, sz * s)) for t, sz in word)
    space = probe.textlength(" ", font=font_for(family, it["size"] * s))
    w = it["w"] * s
    lines, line, lw = [], [], 0
    for word in words:
        ww = wlen(word)
        if line and lw + space + ww > w:
            lines.append((line, lw))
            line, lw = [word], ww
        else:
            lw = ww if not line else lw + space + ww
            line.append(word)
    lines.append((line, lw))
    lh = it["size"] * s * 1.2
    y = it["y"] * s + (it["h"] * s - lh * len(lines)) / 2
    color = rgb(it["color"]) + (int(255 * (1 - it["tT"])),)
    stroke = it.get("stroke")
    d = ImageDraw.Draw(layer)
    for line, lw in lines:
        x = it["x"] * s if it["align"] == "Left" else (it["x"] * s + w - lw if it["align"] == "Right" else it["x"] * s + (w - lw) / 2)
        for wi, word in enumerate(line):
            if wi:
                x += space
            for t, sz in word:
                f = font_for(family, sz * s)
                base = y + lh * .82 - f.getmetrics()[0]
                kw = {}
                if stroke:
                    kw = {"stroke_width": max(1, round(stroke[1] * s)), "stroke_fill": rgb(stroke[0]) + (int(255 * (1 - stroke[2])),)}
                d.text((x, base), t, font=f, fill=color, **kw)
                x += d.textlength(t, font=f)
        y += lh


def draw_emoji(layer, it, s):
    glyph = it["text"]
    try:
        f = ImageFont.truetype(EMOJI, 109)
    except OSError:
        return
    tmp = Image.new("RGBA", (160, 160), (0, 0, 0, 0))
    ImageDraw.Draw(tmp).text((80, 80), glyph, font=f, embedded_color=True, anchor="mm")
    bbox = tmp.getbbox()
    if not bbox:
        return
    tmp = tmp.crop(bbox)
    target = int(it["size"] * s * 1.05)
    k = target / max(tmp.width, tmp.height)
    tmp = tmp.resize((max(1, int(tmp.width * k)), max(1, int(tmp.height * k))), Image.LANCZOS)
    cx, cy = (it["x"] + it["w"] / 2) * s, (it["y"] + it["h"] / 2) * s
    layer.alpha_composite(tmp, (int(cx - tmp.width / 2), int(cy - tmp.height / 2)))


def draw_frame(layer, it, s, night):
    w, h = it["w"] * s, it["h"] * s
    if w < 1 or h < 1:
        return
    pad = int(max(w, h) * .5) + 8
    tile = Image.new("RGBA", (int(w) + 2 * pad, int(h) + 2 * pad), (0, 0, 0, 0))
    r = radius_of(it) * s
    box = [pad, pad, pad + w - 1, pad + h - 1]
    bgT = it["night"] if (night and it.get("night") is not None) else it["bgT"]
    alpha = int(255 * (1 - bgT))
    if alpha > 0:
        mask = Image.new("L", tile.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle(box, radius=r, fill=alpha)
        if it.get("grad"):
            # UIGradient multiplies the background colour.
            bg = rgb(it["bg"])
            c0 = tuple(a * b // 255 for a, b in zip(rgb(it["grad"][0]), bg))
            c1 = tuple(a * b // 255 for a, b in zip(rgb(it["grad"][1]), bg))
            colour = Image.new("RGB", tile.size, c0)
            colour.paste(gradient_fill(int(w), int(h), c0, c1), (pad, pad))
            tile.paste(colour, (0, 0), mask)
        else:
            tile.paste(Image.new("RGB", tile.size, rgb(it["bg"])), (0, 0), mask)
        if it["name"] in ("Shadow", "Shadow soft"):
            tile = tile.filter(ImageFilter.GaussianBlur(6 * s / 2))
        if it["name"] == "Crystal glow":
            tile = tile.filter(ImageFilter.GaussianBlur(4 * s / 2))
    if it.get("stroke"):
        sc, th, st = it["stroke"]
        ImageDraw.Draw(tile).rounded_rectangle(box, radius=r, outline=rgb(sc) + (int(255 * (1 - st)),), width=max(1, round(th * s)))
    rot = it.get("rot") or 0
    cx, cy = (it["x"] + it["w"] / 2) * s, (it["y"] + it["h"] / 2) * s
    if rot:
        tile = tile.rotate(-rot, resample=Image.BICUBIC, expand=True)
    if it.get("pivot"):
        px, py, prot = it["pivot"][0] * s, it["pivot"][1] * s, it["pivot"][2]
        a = math.radians(prot)
        dx, dy = cx - px, cy - py
        cx, cy = px + dx * math.cos(a) - dy * math.sin(a), py + dx * math.sin(a) + dy * math.cos(a)
        tile = tile.rotate(-prot, resample=Image.BICUBIC, expand=True)
    layer.alpha_composite(tile, (int(cx - tile.width / 2), int(cy - tile.height / 2)))


def render_plaque(sign, night):
    s = K
    layer = Image.new("RGBA", (int(sign["w"] * s), int(sign["h"] * s)), (0, 0, 0, 0))
    for it in sorted(sign["items"], key=lambda i: i["z"]):
        if it["class"] == "TextLabel":
            if it["name"] == "Crest glyph" or EMOJI_RE.search(it.get("text") or ""):
                draw_emoji(layer, it, s)
            elif it.get("text"):
                draw_text(layer, it, s, night)
        else:
            draw_frame(layer, it, s, night)
    if night:
        # LightInfluence 0.15: the plaque stays ~90% self-lit after dusk.
        r, g, b, a = layer.split()
        layer = Image.merge("RGBA", [c.point(lambda v: int(v * .9)) for c in (r, g, b)] + [a])
    return layer


def backdrop(night):
    s = K
    w, h = CELL_W * s, CELL_H * s
    sky = gradient_fill(w, h, (20, 26, 52) if night else (122, 170, 214), (40, 44, 70) if night else (196, 222, 236)).convert("RGBA")
    d = ImageDraw.Draw(sky)
    ground = (46, 62, 44) if night else (118, 156, 92)
    d.polygon([(0, h * .8), (w * .3, h * .76), (w * .7, h * .77), (w, h * .79), (w, h), (0, h)], fill=ground)
    d.polygon([(0, h * .86), (w, h * .88), (w, h), (0, h)], fill=tuple(int(c * .8) for c in ground))
    return sky


def nameplate():
    """The NPC nameplate (npc.server.lua) for comparison."""
    items = [
        {"class": "Frame", "name": "Plate", "x": 10, "y": 3, "w": 200, "h": 46, "z": 1, "rot": 0, "bg": "091923", "bgT": .25, "corner": [0, 8],
         "stroke": ["F9CC77", 1, .4]},
        {"class": "TextLabel", "name": "NpcName", "x": 16, "y": 6, "w": 188, "h": 21, "z": 2, "rot": 0, "bg": "000000", "bgT": 1, "text": "Hesper Furrowmilde",
         "size": 17, "color": "F9CC77", "tT": 0, "align": "Center", "font": "BuilderSans"},
        {"class": "TextLabel", "name": "NpcTitle", "x": 16, "y": 26, "w": 188, "h": 21, "z": 2, "rot": 0, "bg": "000000", "bgT": 1, "text": "Millwarden of the Sunwheel",
         "size": 13, "color": "9EE7D2", "tT": 0, "align": "Center", "font": "BuilderSans"},
    ]
    return {"title": "NPC nameplate (for comparison)", "kind": "npc", "w": 220, "h": 52, "items": items}


def render_cell(sign, night):
    s = K
    cell = backdrop(night)
    plaque = render_plaque(sign, night)
    cx = CELL_W * s / 2
    top = max(8 * s, (CELL_H * s * .74 - plaque.height) / 2)
    cell.alpha_composite(plaque, (int(cx - plaque.width / 2), int(top)))
    d = ImageDraw.Draw(cell)
    if sign["kind"] != "npc":
        # Ground anchor: the invisible part the plaque floats over.
        ay = CELL_H * s * .8
        d.ellipse([cx - 22 * s, ay - 5 * s, cx + 22 * s, ay + 5 * s], fill=(0, 0, 0, 70))
        d.line([(cx, top + plaque.height), (cx, ay)], fill=(255, 255, 255, 60), width=s)
    return cell.convert("RGB").resize((CELL_W, CELL_H), Image.LANCZOS)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    night = "--night" in sys.argv
    signs = json.load(open(args[0]))
    if "--nameplate" in sys.argv:
        signs.append(nameplate())
    columns = min(3, len(signs))
    rows = math.ceil(len(signs) / columns)
    sheet = Image.new("RGB", (columns * (CELL_W + 8) + 8, rows * (CELL_H + 28) + 8), (24, 34, 47))
    draw = ImageDraw.Draw(sheet)
    label = ImageFont.truetype(SANS, 15)
    for i, sign in enumerate(signs):
        x, y = 8 + i % columns * (CELL_W + 8), 8 + i // columns * (CELL_H + 28)
        sheet.paste(render_cell(sign, night), (x, y))
        theme = f", {sign['theme']}" if sign.get("theme") else ""
        draw.text((x + 4, y + CELL_H + 5), f"{sign['title']}  ({sign['kind']}{theme})", fill=(220, 230, 235), font=label)
    sheet.save(args[1])
    print(f"Rendered {len(signs)} signs to {args[1]}")


if __name__ == "__main__":
    main()
