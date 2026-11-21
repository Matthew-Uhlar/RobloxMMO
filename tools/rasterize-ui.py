#!/usr/bin/env python3
"""Approximate Roblox GUI layout engine + Pillow rasterizer.

Input: JSON trees written by tools/render-ui.luau (one file per screen size,
each holding several "shots": the PlayerGui's ScreenGuis after a page was drawn).
Output: <out>/<label>/<shot>.png (and <shot>-full.png with --full: the atlas
ScrollingFrame unrolled to its whole canvas height).

This is NOT Roblox. It implements the subset of the layout model the atlas uses:
UDim2 Position/Size + AnchorPoint, UIListLayout, UIGridLayout, UIPadding,
UISizeConstraint, UIAspectRatioConstraint, UITextSizeConstraint, AutomaticSize,
ScrollingFrame canvases (+AutomaticCanvasSize) and clipping, ClipsDescendants,
Visible, ZIndex (Sibling behaviour), BackgroundTransparency, UICorner, UIStroke
(Contextual vs Border), UIGradient (colour/transparency, approximated), Rotation
(drawn, not laid out), TextLabel/TextButton/TextBox text with RichText,
TextWrapped, TextScaled, TextTruncate, TextStroke, ImageLabel as a tint, and
ViewportFrame as a flat projection of the art-catalog shape.
Fonts: DejaVu Sans (Gotham), DejaVu Sans Bold (GothamBold), DejaVu Serif Bold
(Antique). Metrics therefore differ slightly from Roblox's.
Run Python with -I (isolated mode).
"""
import argparse
import json
import math
import os
import re
import sys
from functools import lru_cache

from PIL import Image, ImageDraw, ImageFont

S = 2  # supersampling factor
TOUCH_MIN = 44  # minimum touch target (px) on phone-sized screens (height < 500)
HERE = os.path.dirname(os.path.abspath(__file__))
DEJAVU = "/usr/share/fonts/truetype/dejavu/"
INTER = "/usr/share/fonts/opentype/inter/"
# Stand-ins for Roblox fonts: Inter for Builder Sans (same humanist-grotesque
# proportions), the vendored OFL Fredoka One for FredokaOne, DejaVu for the
# legacy Gotham/Antique faces. Each kind lists candidates; the first file that
# exists is used, and glyphs it lacks fall back to DejaVu (as Roblox falls back
# to its own symbol fonts).
FONT_CANDIDATES = {
    "regular": [DEJAVU + "DejaVuSans.ttf"],
    "bold": [DEJAVU + "DejaVuSans-Bold.ttf"],
    "serif": [DEJAVU + "DejaVuSerif-Bold.ttf"],
    "b-regular": [INTER + "Inter-Regular.otf", DEJAVU + "DejaVuSans.ttf"],
    "b-medium": [INTER + "Inter-Medium.otf", DEJAVU + "DejaVuSans.ttf"],
    "b-bold": [INTER + "Inter-Bold.otf", DEJAVU + "DejaVuSans-Bold.ttf"],
    "b-heavy": [INTER + "Inter-ExtraBold.otf", DEJAVU + "DejaVuSans-Bold.ttf"],
    "display": [os.path.join(HERE, "fonts", "FredokaOne-Regular.ttf"), INTER + "Inter-Black.otf", DEJAVU + "DejaVuSans-Bold.ttf"],
    # Roblox "Arcade" is Press Start 2P (vendored, OFL).
    "pixel": [os.path.join(HERE, "fonts", "PressStart2P-Regular.ttf"), DEJAVU + "DejaVuSans-Bold.ttf"],
}
FALLBACK = {"regular": DEJAVU + "DejaVuSans.ttf", "bold": DEJAVU + "DejaVuSans-Bold.ttf"}
LIGHT_KINDS = {"regular", "b-regular", "b-medium"}
FONTS = {kind: next((path for path in paths if os.path.exists(path)), paths[-1]) for kind, paths in FONT_CANDIDATES.items()}


def read_cmap(path):
    """Set of code points a TrueType/OpenType font maps (cmap formats 4 and 12)."""
    import struct
    try:
        with open(path, "rb") as fh:
            data = fh.read()
    except OSError:
        return None
    try:
        num_tables = struct.unpack(">H", data[4:6])[0]
        cmap = None
        for i in range(num_tables):
            tag, _, offset, _ = struct.unpack(">4sIII", data[12 + 16 * i:28 + 16 * i])
            if tag == b"cmap":
                cmap = offset
        if cmap is None:
            return None
        count = struct.unpack(">H", data[cmap + 2:cmap + 4])[0]
        points = set()
        for i in range(count):
            _, _, sub = struct.unpack(">HHI", data[cmap + 4 + 8 * i:cmap + 12 + 8 * i])
            base = cmap + sub
            fmt = struct.unpack(">H", data[base:base + 2])[0]
            if fmt == 4:
                segx2 = struct.unpack(">H", data[base + 6:base + 8])[0]
                ends = struct.unpack(">%dH" % (segx2 // 2), data[base + 14:base + 14 + segx2])
                starts = struct.unpack(">%dH" % (segx2 // 2), data[base + 16 + segx2:base + 16 + 2 * segx2])
                for a, b in zip(starts, ends):
                    if a != 0xFFFF:
                        points.update(range(a, b + 1))
            elif fmt == 12:
                groups = struct.unpack(">I", data[base + 12:base + 16])[0]
                for g in range(groups):
                    a, b, _ = struct.unpack(">III", data[base + 16 + 12 * g:base + 28 + 12 * g])
                    points.update(range(a, min(b, a + 65536) + 1))
        return points
    except (struct.error, IndexError):
        return None


@lru_cache(maxsize=None)
def coverage(path):
    return read_cmap(path)


GUI = {"Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame", "ViewportFrame", "CanvasGroup"}
TEXT = {"TextLabel", "TextButton", "TextBox"}
DEFAULT_BG = (163, 162, 165)
DEFAULT_TEXT = (27, 42, 53)


def hex2rgb(value, default=(255, 255, 255)):
    if not isinstance(value, str) or not value.startswith("#") or len(value) != 7:
        return default
    return tuple(int(value[i:i + 2], 16) for i in (1, 3, 5))


class Node:
    __slots__ = ("cls", "p", "kids", "comps", "shape", "tint", "uid", "scene")
    counter = 0

    def __init__(self, raw):
        self.cls = raw["class"]
        self.p = raw.get("props") or {}
        self.shape = raw.get("shape")
        self.tint = raw.get("tint")
        self.scene = raw.get("scene")
        self.kids = []
        self.comps = {}
        Node.counter += 1
        self.uid = Node.counter
        for i, child in enumerate(raw.get("children") or []):
            node = Node(child)
            if node.cls in GUI:
                self.kids.append(node)
            else:
                self.comps.setdefault(node.cls, []).append(node)

    def get(self, key, default=None):
        value = self.p.get(key)
        return default if value is None else value

    def comp(self, cls):
        found = self.comps.get(cls)
        return found[0] if found else None

    @property
    def visible(self):
        return self.get("Visible", True) is not False

    @property
    def name(self):
        return self.get("Name", self.cls)


# ---------------------------------------------------------------------------
# Text
# ---------------------------------------------------------------------------
@lru_cache(maxsize=1024)
def font_file(path, px):
    return ImageFont.truetype(path, max(1, int(round(px))))


def font(kind, px):
    return font_file(FONTS[kind], px)


def font_kind(name, bold=False):
    name = name or "Legacy"
    if name == "Antique":
        return "serif"
    if name == "Arcade":
        return "pixel"
    if name == "FredokaOne":
        return "display"
    if name.startswith("BuilderSans"):
        if "ExtraBold" in name:
            return "b-heavy"
        if bold or "Bold" in name:
            return "b-bold"
        return "b-medium" if "Medium" in name else "b-regular"
    if bold or any(k in name for k in ("Bold", "Black", "Heavy", "Semibold")):
        return "bold"
    return "regular"


@lru_cache(maxsize=200000)
def glyph_runs(kind, text):
    """Split text into (font path, substring) runs, falling back for missing glyphs."""
    primary = FONTS[kind]
    have = coverage(primary)
    if have is None:
        return ((primary, text),)
    backup = FALLBACK["regular" if kind in LIGHT_KINDS else "bold"]
    runs = []
    for ch in text:
        path = primary if (ord(ch) in have or ch in " \n") else backup
        if runs and runs[-1][0] == path:
            runs[-1][1].append(ch)
        else:
            runs.append((path, [ch]))
    return tuple((path, "".join(chars)) for path, chars in runs)


@lru_cache(maxsize=200000)
def advance(kind, size, text):
    return sum(font_file(path, size * S).getlength(part) for path, part in glyph_runs(kind, text)) / S


ENTITIES = {"&lt;": "<", "&gt;": ">", "&amp;": "&", "&quot;": '"', "&apos;": "'"}
TAG = re.compile(r"<(/?)([a-zA-Z]+)([^>]*)>")


def unescape(text):
    return re.sub(r"&(lt|gt|amp|quot|apos);", lambda m: ENTITIES[m.group(0)], text)


def rich_runs(text, rich, base):
    """Split text into styled runs: list of (text, style dict)."""
    if not rich:
        return [(text, dict(base))]
    runs, stack, pos = [], [dict(base)], 0
    for m in TAG.finditer(text):
        if m.start() > pos:
            runs.append((unescape(text[pos:m.start()]), dict(stack[-1])))
        pos = m.end()
        closing, tag, attrs = m.group(1), m.group(2).lower(), m.group(3)
        if tag == "br":
            runs.append(("\n", dict(stack[-1])))
            continue
        if closing:
            if len(stack) > 1:
                stack.pop()
            continue
        style = dict(stack[-1])
        if tag == "font":
            c = re.search(r'color\s*=\s*["\']#([0-9a-fA-F]{6})["\']', attrs)
            if c:
                style["color"] = hex2rgb("#" + c.group(1))
            c = re.search(r'color\s*=\s*["\']rgb\((\d+),\s*(\d+),\s*(\d+)\)["\']', attrs)
            if c:
                style["color"] = tuple(int(c.group(i)) for i in (1, 2, 3))
            z = re.search(r'size\s*=\s*["\'](\d+)["\']', attrs)
            if z:
                style["size"] = int(z.group(1))
        elif tag == "b":
            style["bold"] = True
        elif tag == "uppercase" or tag == "uc":
            style["upper"] = True
        stack.append(style)
    if pos < len(text):
        runs.append((unescape(text[pos:]), dict(stack[-1])))
    return runs


def style_kind(style):
    return font_kind(style["font"], style.get("bold"))


def layout_text(text, rich, base, size, wrap_width, broken=None):
    """Return (lines, widths, heights). lines: list of list of (str, style).
    broken (a list) receives True when a word had to be split by characters."""
    runs = rich_runs(text, rich, base)
    atoms = []  # (text, style) where text is a word, space run or "\n"
    for run_text, style in runs:
        if style.get("upper"):
            run_text = run_text.upper()
        for piece in re.findall(r"\n| +|[^ \n]+", run_text):
            atoms.append((piece, style))
    lines, widths = [[]], [0.0]
    soft = [False]  # line started by a soft wrap (leading spaces dropped)

    def width_of(piece, style):
        return advance(style_kind(style), style.get("size") or size, piece)

    for piece, style in atoms:
        if piece == "\n":
            lines.append([])
            widths.append(0.0)
            soft.append(False)
            continue
        w = width_of(piece, style)
        if wrap_width is not None and piece.strip() and widths[-1] + w > wrap_width + 0.5 and lines[-1]:
            # wrap before this word; drop trailing spaces
            while lines[-1] and not lines[-1][-1][0].strip():
                widths[-1] -= width_of(lines[-1][-1][0], lines[-1][-1][1])
                lines[-1].pop()
            lines.append([])
            widths.append(0.0)
            soft.append(True)
        if wrap_width is not None and not piece.strip() and not lines[-1] and soft[-1]:
            continue  # no leading spaces on wrapped lines
        if wrap_width is not None and w > wrap_width and piece.strip():
            # break a long word by characters
            if broken is not None:
                broken.append(True)
            chunk = ""
            for ch in piece:
                cw = width_of(chunk + ch, style)
                if widths[-1] + cw > wrap_width and (chunk or lines[-1]):
                    if chunk:
                        lines[-1].append((chunk, style))
                        widths[-1] += width_of(chunk, style)
                    lines.append([])
                    widths.append(0.0)
                    soft.append(True)
                    chunk = ch
                else:
                    chunk += ch
            if chunk:
                lines[-1].append((chunk, style))
                widths[-1] += width_of(chunk, style)
            continue
        lines[-1].append((piece, style))
        widths[-1] += w
    heights = []
    for line in lines:
        heights.append(max([st.get("size") or size for _, st in line] or [size]))
    return lines, widths, heights


def text_props(node):
    base = {"font": node.get("Font", "Legacy"), "color": None}
    return base


def text_of(node):
    text = node.get("Text")
    if text is None:
        text = {"TextLabel": "Label", "TextButton": "Button", "TextBox": ""}.get(node.cls, "")
    placeholder = False
    if node.cls == "TextBox" and text == "" and node.get("PlaceholderText"):
        text, placeholder = node.get("PlaceholderText"), True
    return str(text), placeholder


def size_constraint(node):
    c = node.comp("UITextSizeConstraint")
    lo, hi = 1, 100
    if c:
        lo = c.get("MinTextSize", 1)
        hi = c.get("MaxTextSize", 100)
    return lo, hi


def text_block(node, w, h):
    """Resolve the text layout for a text object of content size w x h."""
    text, placeholder = text_of(node)
    rich = node.get("RichText", False) is True
    base = text_props(node)
    wrapped = node.get("TextWrapped", False) is True
    scaled = node.get("TextScaled", False) is True
    size = node.get("TextSize", 14)
    if scaled:
        lo, hi = size_constraint(node)
        best = lo
        a, b = int(lo), int(hi)
        while a <= b:
            mid = (a + b) // 2
            broken = []
            lines, widths, heights = layout_text(text, rich, base, mid, w, broken)
            fits = sum(heights) <= h + 0.5 and max(widths or [0]) <= w + 0.5 and not broken
            if fits:
                best = mid
                a = mid + 1
            else:
                b = mid - 1
        size = best
        lines, widths, heights = layout_text(text, rich, base, size, w)
    else:
        lines, widths, heights = layout_text(text, rich, base, size, w if wrapped else None)
    return {"lines": lines, "widths": widths, "heights": heights, "size": size, "placeholder": placeholder}


def text_bounds(node, wrap_w):
    text, _ = text_of(node)
    if text == "":
        return 0, 0
    rich = node.get("RichText", False) is True
    wrapped = node.get("TextWrapped", False) is True
    size = node.get("TextSize", 14)
    lines, widths, heights = layout_text(text, rich, text_props(node), size, wrap_w if wrapped else None)
    return max(widths or [0]), sum(heights)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
def udim2(node, key):
    v = node.get(key)
    return v if isinstance(v, list) and len(v) == 4 else [0, 0, 0, 0]


def udim(v, ref):
    if isinstance(v, list) and len(v) == 2:
        return v[0] * ref + v[1]
    return 0


def padding(node, w, h):
    pad = node.comp("UIPadding")
    if not pad:
        return 0, 0, 0, 0
    return (udim(pad.get("PaddingLeft"), w), udim(pad.get("PaddingTop"), h),
            udim(pad.get("PaddingRight"), w), udim(pad.get("PaddingBottom"), h))


def clamp_size(node, w, h):
    c = node.comp("UISizeConstraint")
    if c:
        mx = c.get("MaxSize", [math.inf, math.inf])
        mn = c.get("MinSize", [0, 0])
        w = max(mn[0], min(w, mx[0]))
        h = max(mn[1], min(h, mx[1]))
    a = node.comp("UIAspectRatioConstraint")
    if a:
        ratio = a.get("AspectRatio", 1) or 1
        if a.get("AspectType", "FitWithinMaxSize") == "FitWithinMaxSize":
            if h > 0 and w / h > ratio:
                w = h * ratio
            else:
                h = w / ratio
        elif a.get("DominantAxis", "Width") == "Width":
            h = w / ratio
        else:
            w = h * ratio
    return max(0, w), max(0, h)


class Layout:
    def __init__(self):
        self.cache = {}
        self.issues = []

    def measure(self, node, pw, ph, forced=None):
        key = (node.uid, round(pw, 3), round(ph, 3), forced)
        hit = self.cache.get(key)
        if hit:
            return hit
        if forced:
            w, h = forced
        else:
            s = udim2(node, "Size")
            w, h = s[0] * pw + s[1], s[2] * ph + s[3]
        w, h = clamp_size(node, w, h)
        auto = node.get("AutomaticSize", "None")
        if auto != "None":
            pl, pt, pr, pb = padding(node, w, h)
            cw, ch = w - pl - pr, h - pt - pb
            ew, eh, _ = self.children(node, cw, ch)
            if node.cls in TEXT:
                tw, th = text_bounds(node, None if "X" in auto else cw)
                ew, eh = max(ew, tw), max(eh, th)
            if "X" in auto:
                w = max(w, ew + pl + pr)
            if "Y" in auto:
                h = max(h, eh + pt + pb)
            w, h = clamp_size(node, w, h)
        self.cache[key] = (w, h)
        return w, h

    def children(self, node, cw, ch):
        """Place visible GUI children inside a content box. Returns (extentW, extentH, placements)."""
        kids = [k for k in node.kids if k.visible]
        out = []
        lst, grid = node.comp("UIListLayout"), node.comp("UIGridLayout")
        if lst:
            order = lst.get("SortOrder", "LayoutOrder")
            idx = {k.uid: i for i, k in enumerate(kids)}
            if order == "Name":
                kids.sort(key=lambda k: (k.name, idx[k.uid]))
            else:
                kids.sort(key=lambda k: (k.get("LayoutOrder", 0), idx[k.uid]))
            vertical = lst.get("FillDirection", "Vertical") == "Vertical"
            gap = udim(lst.get("Padding"), ch if vertical else cw)
            cursor, cross = 0.0, 0.0
            for k in kids:
                w, h = self.measure(k, cw, ch)
                if vertical:
                    out.append([k, 0, cursor, w, h])
                    cursor += h + gap
                    cross = max(cross, w)
                else:
                    out.append([k, cursor, 0, w, h])
                    cursor += w + gap
                    cross = max(cross, h)
            total = max(0.0, cursor - gap) if kids else 0.0
            ha = lst.get("HorizontalAlignment", "Left")
            va = lst.get("VerticalAlignment", "Top")
            for item in out:
                if vertical:
                    if ha == "Center":
                        item[1] = (cw - item[3]) / 2
                    elif ha == "Right":
                        item[1] = cw - item[3]
                    if va == "Center":
                        item[2] += (ch - total) / 2
                    elif va == "Bottom":
                        item[2] += ch - total
                else:
                    if va == "Center":
                        item[2] = (ch - item[4]) / 2
                    elif va == "Bottom":
                        item[2] = ch - item[4]
                    if ha == "Center":
                        item[1] += (cw - total) / 2
                    elif ha == "Right":
                        item[1] += cw - total
            ew = cross if vertical else total
            eh = total if vertical else cross
            return ew, eh, out
        if grid:
            cs = grid.get("CellSize", [0, 100, 0, 100])
            cp = grid.get("CellPadding", [0, 5, 0, 5])
            cellw, cellh = cs[0] * cw + cs[1], cs[2] * ch + cs[3]
            px, py = cp[0] * cw + cp[1], cp[2] * ch + cp[3]
            idx = {k.uid: i for i, k in enumerate(kids)}
            if grid.get("SortOrder", "LayoutOrder") == "Name":
                kids.sort(key=lambda k: (k.name, idx[k.uid]))
            else:
                kids.sort(key=lambda k: (k.get("LayoutOrder", 0), idx[k.uid]))
            per = max(1, int((cw + px + 0.001) // (cellw + px))) if cellw + px > 0 else 1
            maxcells = grid.get("FillDirectionMaxCells", 0) or 0
            if maxcells > 0:
                per = min(per, maxcells)
            horizontal = grid.get("FillDirection", "Horizontal") == "Horizontal"
            rows = 0
            for i, k in enumerate(kids):
                r, c = (i // per, i % per) if horizontal else (i % per, i // per)
                w, h = self.measure(k, cw, ch, (cellw, cellh))
                out.append([k, c * (cellw + px), r * (cellh + py), w, h])
                rows = max(rows, r + 1)
            ncols = min(per, len(kids)) if horizontal else math.ceil(len(kids) / per)
            ew = ncols * cellw + max(0, ncols - 1) * px
            eh = rows * cellh + max(0, rows - 1) * py
            ha = grid.get("HorizontalAlignment", "Left")
            if ha in ("Center", "Right"):
                shift = (cw - ew) / (2 if ha == "Center" else 1)
                for item in out:
                    item[1] += shift
            return ew, eh, out
        ew = eh = 0.0
        for k in kids:
            w, h = self.measure(k, cw, ch)
            pos = udim2(k, "Position")
            ap = k.get("AnchorPoint", [0, 0])
            x = pos[0] * cw + pos[1] - ap[0] * w
            y = pos[2] * ch + pos[3] - ap[1] * h
            out.append([k, x, y, w, h])
            ew, eh = max(ew, x + w), max(eh, y + h)
        return ew, eh, out


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------
def gradient_color(grad, t):
    seq = grad.get("Color")
    if not isinstance(seq, dict) or "seq" not in seq:
        return (255, 255, 255)
    keys = [(k[0], hex2rgb(k[1])) for k in seq["seq"]]
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, c0), (t1, c1) in zip(keys, keys[1:]):
        if t <= t1:
            f = 0 if t1 == t0 else (t - t0) / (t1 - t0)
            return tuple(int(c0[i] + (c1[i] - c0[i]) * f) for i in range(3))
    return keys[-1][1]


def gradient_alpha(grad, t):
    seq = grad.get("Transparency")
    if not isinstance(seq, dict) or "nseq" not in seq:
        return 1.0
    keys = seq["nseq"]
    if t <= keys[0][0]:
        return 1 - keys[0][1]
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t <= t1:
            f = 0 if t1 == t0 else (t - t0) / (t1 - t0)
            return 1 - (v0 + (v1 - v0) * f)
    return 1 - keys[-1][1]


def mul(c, m):
    return tuple(int(c[i] * m[i] / 255) for i in range(3))


def gradient_image(grad, w, h, color, alpha):
    """RGBA image w x h of colour*gradient (Roblox UIGradient, rotation in degrees)."""
    rot = math.radians(grad.get("Rotation", 0) or 0)
    dx, dy = math.cos(rot), math.sin(rot)
    steps = 32
    lut = [mul(color, gradient_color(grad, i / (steps - 1))) for i in range(steps)]
    alut = [int(255 * alpha * gradient_alpha(grad, i / (steps - 1))) for i in range(steps)]
    small_w, small_h = max(1, min(w, 48)), max(1, min(h, 48))
    img = Image.new("RGBA", (small_w, small_h))
    px = img.load()
    for yy in range(small_h):
        for xx in range(small_w):
            u = (xx + 0.5) / small_w - 0.5
            v = (yy + 0.5) / small_h - 0.5
            t = 0.5 + (u * dx + v * dy) / (abs(dx) + abs(dy) + 1e-9)
            t = min(1, max(0, t))
            i = int(t * (steps - 1))
            c = lut[i]
            px[xx, yy] = (c[0], c[1], c[2], alut[i])
    return img.resize((max(1, w), max(1, h)), Image.BILINEAR)


def corner_radius(node, w, h):
    c = node.comp("UICorner")
    if not c:
        return 0
    r = udim(c.get("CornerRadius", [0, 8]), min(w, h))
    return max(0, min(r, min(w, h) / 2))


def stroke_of(node):
    st = node.comp("UIStroke")
    if not st or st.get("Enabled", True) is False:
        return None
    color = hex2rgb(st.get("Color"), (0, 0, 0))
    grad = st.comp("UIGradient")
    if grad is not None and grad.get("Enabled", True) is False:
        grad = None
    flat = mul(color, gradient_color(grad, 0.5)) if grad else color
    mode = st.get("ApplyStrokeMode", "Contextual")
    return {"color": flat, "base": color, "grad": grad, "alpha": 1 - (st.get("Transparency", 0) or 0), "thickness": st.get("Thickness", 1) or 1,
            "border": mode == "Border" or node.cls not in TEXT}


class Painter:
    def __init__(self, width, height, art):
        self.w, self.h = width, height
        self.img = Image.new("RGBA", (width * S, height * S), (0, 0, 0, 255))
        self.art = art
        self.issues = []

    def composite(self, patch, x, y, clip):
        """Alpha-composite patch (supersampled) at supersampled x,y inside clip (unscaled rect)."""
        x, y = int(round(x)), int(round(y))
        cx0, cy0, cx1, cy1 = [int(round(v * S)) for v in clip]
        cx0, cy0 = max(cx0, 0), max(cy0, 0)
        cx1, cy1 = min(cx1, self.img.width), min(cy1, self.img.height)
        sx0, sy0 = max(x, cx0), max(y, cy0)
        sx1, sy1 = min(x + patch.width, cx1), min(y + patch.height, cy1)
        if sx1 <= sx0 or sy1 <= sy0:
            return
        region = patch.crop((sx0 - x, sy0 - y, sx1 - x, sy1 - y))
        self.img.alpha_composite(region, (sx0, sy0))

    def backdrop(self):
        """Placeholder world: sky gradient, sea and a few island silhouettes."""
        W, H = self.img.size
        top, mid, sea = (58, 98, 122), (128, 172, 178), (34, 74, 86)
        d = ImageDraw.Draw(self.img)
        horizon = int(H * 0.62)
        for yy in range(H):
            if yy < horizon:
                f = yy / horizon
                c = tuple(int(top[i] + (mid[i] - top[i]) * f) for i in range(3))
            else:
                f = (yy - horizon) / max(1, H - horizon)
                c = tuple(int(sea[i] * (1 - 0.35 * f)) for i in range(3))
            d.line([(0, yy), (W, yy)], fill=c + (255,))
        for cx, cy, r, col in ((0.18, 0.6, 0.16, (60, 92, 70)), (0.7, 0.55, 0.22, (70, 104, 78)), (0.45, 0.66, 0.1, (88, 120, 84))):
            d.ellipse([W * (cx - r), H * cy - H * r * 0.35, W * (cx + r), H * cy + H * r * 0.25], fill=col + (255,))

    # -- element drawing ----------------------------------------------------
    def draw_box(self, node, x, y, w, h, clip):
        if w * S < 1 or h * S < 1:
            return
        bt = node.get("BackgroundTransparency", 0)
        alpha = 1 - (bt if isinstance(bt, (int, float)) else 0)
        color = hex2rgb(node.get("BackgroundColor3"), DEFAULT_BG)
        radius = corner_radius(node, w, h)
        stroke = stroke_of(node)
        grad = node.comp("UIGradient")
        if grad is not None and grad.get("Enabled", True) is False:
            grad = None
        rot = node.get("Rotation", 0) or 0
        border = stroke if stroke and stroke["border"] else None
        margin = int(math.ceil(border["thickness"])) + 1 if border else 0
        if alpha <= 0.003 and not border and not (node.get("BorderSizePixel", 1) and not node.comp("UICorner") and alpha > 0):
            return
        pw, ph = int(round((w + 2 * margin) * S)), int(round((h + 2 * margin) * S))
        if pw <= 0 or ph <= 0 or pw > 20000 or ph > 20000:
            return
        patch = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
        m = margin * S
        box = [m, m, m + w * S - 1, m + h * S - 1]
        if alpha > 0.003:
            if grad is not None:
                mask = Image.new("L", (pw, ph), 0)
                ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius * S, fill=255)
                fill = gradient_image(grad, int(w * S), int(h * S), color, alpha)
                layer = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
                layer.paste(fill, (m, m))
                a = layer.getchannel("A")
                from PIL import ImageChops
                layer.putalpha(ImageChops.multiply(a, mask))
                patch.alpha_composite(layer)
            else:
                ImageDraw.Draw(patch).rounded_rectangle(box, radius=radius * S, fill=color + (int(255 * alpha),))
        if border and w > 0 and h > 0:
            t = border["thickness"] * S
            outer = [m - t, m - t, m + w * S - 1 + t, m + h * S - 1 + t]
            if border["grad"] is not None:
                # Gradient rim: colour and transparency follow the UIGradient (with rotation).
                from PIL import ImageChops
                ring = Image.new("L", (pw, ph), 0)
                ImageDraw.Draw(ring).rounded_rectangle(outer, radius=(radius * S + t) if radius else 0, outline=255, width=max(1, int(round(t))))
                ox, oy = int(max(0, m - t)), int(max(0, m - t))
                ow, oh = int(min(pw, m + w * S + t)) - ox, int(min(ph, m + h * S + t)) - oy
                fill = gradient_image(border["grad"], max(1, ow), max(1, oh), border["base"], border["alpha"])
                layer = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
                layer.paste(fill, (ox, oy))
                layer.putalpha(ImageChops.multiply(layer.getchannel("A"), ring))
                patch.alpha_composite(layer)
            else:
                # Thick rims on tiny boxes: keep the corner radius within the box.
                rr = min((radius * S + t) if radius else 0, max(0, (outer[2] - outer[0]) / 2 - 1), max(0, (outer[3] - outer[1]) / 2 - 1))
                ImageDraw.Draw(patch).rounded_rectangle(outer, radius=rr, outline=border["color"] + (int(255 * border["alpha"]),), width=max(1, int(round(t))))
        elif not node.comp("UICorner") and (node.get("BorderSizePixel", 1) or 0) > 0 and alpha > 0.003:
            bc = hex2rgb(node.get("BorderColor3"), (27, 42, 53))
            bw = node.get("BorderSizePixel", 1) * S
            ImageDraw.Draw(patch).rectangle([m - bw, m - bw, m + w * S - 1 + bw, m + h * S - 1 + bw], outline=bc + (int(255 * alpha),), width=int(bw))
        if rot:
            patch = patch.rotate(-rot, resample=Image.BICUBIC, expand=True)
            cx, cy = (x + w / 2) * S, (y + h / 2) * S
            self.composite(patch, cx - patch.width / 2, cy - patch.height / 2, clip)
        else:
            self.composite(patch, (x - margin) * S, (y - margin) * S, clip)

    def draw_viewport(self, node, x, y, w, h, clip):
        if node.scene:
            if w >= 4 and h >= 4:
                patch = render_scene(node.scene, int(w * S), int(h * S))
                self.composite(patch, x * S, y * S, clip)
            return
        shape = self.art["shapes"].get(node.shape) if node.shape else None
        if not shape or w < 4 or h < 4:
            return
        verts = shape["vertices"]
        palette = self.art["palette"]
        tint_index = self.art.get("tintIndex")
        xs, ys, zs = zip(*verts)
        center = ((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, (max(zs) + min(zs)) / 2)
        radius = max(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
        dvec = (0.7, 0.38, -1.0)
        dl = math.sqrt(sum(c * c for c in dvec))
        eye = tuple(center[i] + dvec[i] / dl * radius * 2 for i in range(3))
        f = tuple((center[i] - eye[i]) for i in range(3))
        fl = math.sqrt(sum(c * c for c in f))
        f = tuple(c / fl for c in f)
        up = (0, 1, 0)
        r = (f[1] * up[2] - f[2] * up[1], f[2] * up[0] - f[0] * up[2], f[0] * up[1] - f[1] * up[0])
        rl = math.sqrt(sum(c * c for c in r))
        r = tuple(c / rl for c in r)
        u = (r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0])
        t = math.tan(math.radians(17))
        pw, ph = int(w * S), int(h * S)
        light = (-1, -1, -2)
        ll = math.sqrt(sum(c * c for c in light))
        light = tuple(-c / ll for c in light)
        tris = []
        for face in shape["faces"]:
            pts = [verts[face[i] - 1] for i in range(3)]
            cam = []
            for p in pts:
                v = tuple(p[i] - eye[i] for i in range(3))
                cx = sum(v[i] * r[i] for i in range(3))
                cy = sum(v[i] * u[i] for i in range(3))
                cz = sum(v[i] * f[i] for i in range(3))
                cz = max(cz, 1e-3)
                cam.append((pw / 2 + cx / (cz * t) * ph / 2, ph / 2 - cy / (cz * t) * ph / 2, cz))
            a, b, c = pts
            e1 = tuple(b[i] - a[i] for i in range(3))
            e2 = tuple(c[i] - a[i] for i in range(3))
            n = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
            nl = math.sqrt(sum(cc * cc for cc in n)) or 1
            n = tuple(cc / nl for cc in n)
            if sum(n[i] * f[i] for i in range(3)) > 0:
                n = tuple(-cc for cc in n)
            diff = max(0.0, sum(n[i] * light[i] for i in range(3)))
            if len(face) > 3 and tint_index and face[3] == tint_index and node.tint:
                base = hex2rgb(node.tint)
            else:
                base = hex2rgb("#" + palette[face[3] - 1]) if len(face) > 3 and 0 < face[3] <= len(palette) else (120, 130, 140)
            k = 0.62 + 0.5 * diff
            col = tuple(min(255, int(base[i] * k)) for i in range(3))
            tris.append((sum(p[2] for p in cam) / 3, [(p[0], p[1]) for p in cam], col))
        tris.sort(key=lambda tri: -tri[0])
        patch = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
        d = ImageDraw.Draw(patch)
        for _, poly, col in tris:
            d.polygon(poly, fill=col + (255,))
        radius_px = corner_radius(node, w, h)
        if radius_px:
            mask = Image.new("L", (pw, ph), 0)
            ImageDraw.Draw(mask).rounded_rectangle([0, 0, pw - 1, ph - 1], radius=radius_px * S, fill=255)
            from PIL import ImageChops
            patch.putalpha(ImageChops.multiply(patch.getchannel("A"), mask))
        self.composite(patch, x * S, y * S, clip)

    def draw_text(self, node, x, y, w, h, clip):
        text, placeholder = text_of(node)
        if text == "":
            return
        tt = node.get("TextTransparency", 0) or 0
        if tt >= 0.99:
            return
        pl, pt, pr, pb = padding(node, w, h)
        cx, cy, cw, chh = x + pl, y + pt, w - pl - pr, h - pt - pb
        block = text_block(node, cw, chh)
        lines, widths, heights, size = block["lines"], block["widths"], block["heights"], block["size"]
        base_color = hex2rgb(node.get("TextColor3"), DEFAULT_TEXT)
        if placeholder:
            base_color = hex2rgb(node.get("PlaceholderColor3"), (178, 178, 178))
        grad = node.comp("UIGradient")
        if grad is not None and grad.get("Enabled", True) is False:
            grad = None
        truncate = node.get("TextTruncate", "None") == "AtEnd"
        wrapped = node.get("TextWrapped", False) is True or node.get("TextScaled", False) is True
        if truncate:
            if wrapped:
                fit = max(1, int((chh + 0.5) // max(1, size)))
                if len(lines) > fit:
                    lines, widths, heights = lines[:fit], widths[:fit], heights[:fit]
                    lines[-1] = lines[-1] + [("…", lines[-1][-1][1] if lines[-1] else {"font": node.get("Font"), "color": None})]
                    widths[-1] = cw + 1  # force the character trim below
            for i, line in enumerate(lines):
                if widths[i] > cw + 0.5:
                    lines[i], widths[i] = self.ellipsize(line, size, cw)
                    self.issues.append(("truncated", node.name, int(cw), re.sub(r"<[^>]+>", "", text)[:50]))
        stroke = stroke_of(node)
        text_stroke = None
        if stroke and not stroke["border"]:
            text_stroke = (stroke["color"], stroke["alpha"], stroke["thickness"])
        sts = node.get("TextStrokeTransparency", 1)
        if sts is not None and sts < 1 and text_stroke is None:
            text_stroke = (hex2rgb(node.get("TextStrokeColor3"), (0, 0, 0)), 1 - sts, 1)
        total_h = sum(heights)
        ya = node.get("TextYAlignment", "Center")
        xa = node.get("TextXAlignment", "Center")
        top = cy if ya == "Top" else (cy + chh - total_h if ya == "Bottom" else cy + (chh - total_h) / 2)
        alpha = 1 - tt
        # draw into a patch covering the text extents (may overflow the box)
        maxw = max(widths or [0])
        left_edge = min(cx, cx + (cw - maxw) / 2 if xa == "Center" else (cx + cw - maxw if xa == "Right" else cx))
        px0, py0 = math.floor(left_edge - 4), math.floor(min(top, cy) - 4)
        pw = int((max(maxw, cw) + 8 + abs(left_edge - cx)) * S) + 2
        phh = int((max(total_h, chh) + 8 + abs(min(top, cy) - cy)) * S) + 2
        if pw <= 0 or phh <= 0 or pw > 20000 or phh > 20000:
            return
        patch = Image.new("RGBA", (pw, phh), (0, 0, 0, 0))
        d = ImageDraw.Draw(patch)
        yy = top
        for i, line in enumerate(lines):
            lw, lh = widths[i], heights[i]
            lx = cx if xa == "Left" else (cx + cw - lw if xa == "Right" else cx + (cw - lw) / 2)
            baseline = yy + lh * 0.5 + 0.36 * lh
            for piece, style in line:
                psize = style.get("size") or size
                kind = style_kind(style)
                col = style.get("color") or base_color
                kw = {}
                if text_stroke and piece.strip():
                    kw = {"stroke_width": max(1, int(round(text_stroke[2] * S * 0.75))), "stroke_fill": text_stroke[0] + (int(255 * text_stroke[1] * alpha),)}
                gx = lx
                for path, part in glyph_runs(kind, piece):
                    f = font_file(path, psize * S)
                    d.text(((gx - px0) * S, (baseline - py0) * S), part, font=f, fill=col + (int(255 * alpha),), anchor="ls", **kw)
                    gx += f.getlength(part) / S
                lx += advance(kind, psize, piece)
            yy += lh
        if grad is not None:
            # UIGradient on a text object tints (and fades) the glyphs across the box.
            from PIL import ImageChops
            gw, gh = max(1, int(w * S)), max(1, int(h * S))
            shade = gradient_image(grad, gw, gh, (255, 255, 255), 1.0)
            tint = Image.new("RGBA", patch.size, (255, 255, 255, 255))
            tint.paste(shade, (int((x - px0) * S), int((y - py0) * S)))
            r, g, b, a = patch.split()
            tr, tg, tb, ta = tint.split()
            patch = Image.merge("RGBA", (ImageChops.multiply(r, tr), ImageChops.multiply(g, tg), ImageChops.multiply(b, tb), ImageChops.multiply(a, ta)))
        self.composite(patch, px0 * S, py0 * S, clip)
        # record readability issues
        if size < 11 and text.strip():
            self.issues.append(("small-text", node.name, round(size, 1), text[:40]))
        if not truncate and not wrapped and maxw > cw + 2 and node.get("ClipsDescendants") is not True:
            self.issues.append(("overflow-x", node.name, int(maxw - cw), re.sub(r"<[^>]+>", "", text)[:50]))
        if total_h > chh + 3 and wrapped:
            self.issues.append(("overflow-y", node.name, int(total_h - chh), re.sub(r"<[^>]+>", "", text)[:50]))

    def ellipsize(self, line, size, maxw):
        out, width = [], 0.0
        flat = []
        for piece, style in line:
            for ch in piece:
                flat.append((ch, style))
        ell_style = flat[-1][1] if flat else {"font": "Gotham", "color": None}
        ell = advance(style_kind(ell_style), ell_style.get("size") or size, "…")
        for ch, style in flat:
            cw = advance(style_kind(style), style.get("size") or size, ch)
            if width + cw + ell > maxw:
                break
            out.append((ch, style))
            width += cw
        # merge back into runs
        runs = []
        for ch, style in out:
            if runs and runs[-1][1] is style:
                runs[-1] = (runs[-1][0] + ch, style)
            else:
                runs.append((ch, style))
        runs.append(("…", ell_style))
        return runs, width + ell


# ---------------------------------------------------------------------------
# 3D scenes (Map Art §32: the Sky Chart miniature). A small z-buffered
# rasterizer over the dumped parts: blocks, wedges, cylinders (axis = local X),
# balls; MeshParts as their boxes (forged meshes only exist in Studio). Flat
# Lambert shading from the ViewportFrame's Ambient / LightColor / LightDirection.
# ---------------------------------------------------------------------------
def _part_faces(part):
    """Local-space polygons [(verts, normal)] for a dumped part."""
    sx, sy, sz = (c / 2 for c in part["size"])
    shape = part.get("shape")
    cls = part.get("class")
    faces = []
    if cls == "Part" and shape == "Cylinder":
        r_y, r_z = sy, sz
        n = 20 if max(sy, sz) > 6 else 10
        ring = [(math.cos(2 * math.pi * i / n), math.sin(2 * math.pi * i / n)) for i in range(n)]
        for i in range(n):
            a, b = ring[i], ring[(i + 1) % n]
            quad = [(-sx, a[0] * r_y, a[1] * r_z), (sx, a[0] * r_y, a[1] * r_z), (sx, b[0] * r_y, b[1] * r_z), (-sx, b[0] * r_y, b[1] * r_z)]
            mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
            faces.append((quad, (0, mid[0], mid[1])))
        faces.append(([(sx, c * r_y, s_ * r_z) for c, s_ in ring], (1, 0, 0)))
        faces.append(([(-sx, c * r_y, s_ * r_z) for c, s_ in reversed(ring)], (-1, 0, 0)))
        return faces
    if cls == "Part" and shape == "Ball":
        r = min(sx, sy, sz)
        lat, lon = 6, 10
        for i in range(lat):
            t0, t1 = math.pi * i / lat - math.pi / 2, math.pi * (i + 1) / lat - math.pi / 2
            for j in range(lon):
                p0, p1 = 2 * math.pi * j / lon, 2 * math.pi * (j + 1) / lon
                pts = [(math.cos(t) * math.cos(p) * r, math.sin(t) * r, math.cos(t) * math.sin(p) * r) for t, p in ((t0, p0), (t0, p1), (t1, p1), (t1, p0))]
                tm, pm = (t0 + t1) / 2, (p0 + p1) / 2
                faces.append((pts, (math.cos(tm) * math.cos(pm), math.sin(tm), math.cos(tm) * math.sin(pm))))
        return faces
    c = [(x, y, z) for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)]
    if cls == "WedgePart":
        # Vertical face at +Z, slope falling towards -Z.
        b0, b1, b2, b3 = (-sx, -sy, -sz), (sx, -sy, -sz), (sx, -sy, sz), (-sx, -sy, sz)
        t2, t3 = (sx, sy, sz), (-sx, sy, sz)
        ln = math.hypot(2 * sy, 2 * sz) or 1
        return [([b0, b1, b2, b3], (0, -1, 0)), ([b3, b2, t2, t3], (0, 0, 1)), ([b0, t3, t2, b1], (0, 2 * sz / ln, -2 * sy / ln)),
                ([b0, b3, t3], (-1, 0, 0)), ([b1, t2, b2], (1, 0, 0))]
    idx = {"x-": [0, 1, 3, 2], "x+": [4, 6, 7, 5], "y-": [0, 4, 5, 1], "y+": [2, 3, 7, 6], "z-": [0, 2, 6, 4], "z+": [1, 5, 7, 3]}
    normals = {"x-": (-1, 0, 0), "x+": (1, 0, 0), "y-": (0, -1, 0), "y+": (0, 1, 0), "z-": (0, 0, -1), "z+": (0, 0, 1)}
    return [([c[i] for i in idx[k]], normals[k]) for k in idx]


def render_scene(scene, pw, ph):
    import numpy as np
    cam = scene["camera"]
    cpos = np.array(cam[0:3], dtype=float)
    crot = np.array(cam[3:12], dtype=float).reshape(3, 3)  # columns: right, up, back
    fov = math.radians(scene.get("fov") or 70)
    k = (ph / 2) / math.tan(fov / 2)
    amb = np.array(hex2rgb(scene.get("ambient"), (150, 150, 150)), dtype=float) / 255
    sun = np.array(hex2rgb(scene.get("light"), (255, 255, 255)), dtype=float) / 255
    ld = np.array(scene.get("lightDirection") or (-1, -1, -1), dtype=float)
    ld = ld / (np.linalg.norm(ld) or 1)
    color = np.zeros((ph, pw, 3), dtype=float)
    alpha = np.zeros((ph, pw), dtype=float)
    zbuf = np.full((ph, pw), np.inf)
    tris = []
    for part in scene["parts"]:
        pos = np.array(part["cf"][0:3], dtype=float)
        rot = np.array(part["cf"][3:12], dtype=float).reshape(3, 3)
        base = np.array(hex2rgb(part.get("color")), dtype=float) / 255
        a = 1 - float(part.get("alpha") or 0)
        neon = part.get("material") == "Neon"
        for verts, normal in _part_faces(part):
            wv = (rot @ np.array(verts, dtype=float).T).T + pos
            n = rot @ np.array(normal, dtype=float)
            centroid = wv.mean(axis=0)
            if np.dot(n, centroid - cpos) >= 0:
                continue  # back face
            rel = (wv - cpos) @ crot  # camera space
            depth = -rel[:, 2]
            if (depth <= 0.5).any():
                continue
            sx = pw / 2 + rel[:, 0] / depth * k
            sy = ph / 2 - rel[:, 1] / depth * k
            if neon:
                shade = np.minimum(1.0, base * 1.25 + 0.1)
            else:
                diffuse = max(0.0, -float(np.dot(n, ld)))
                shade = np.minimum(1.0, base * (amb * 0.62 + sun * diffuse * 0.62) * 1.12)
            for i in range(1, len(verts) - 1):
                tris.append((sx[[0, i, i + 1]], sy[[0, i, i + 1]], depth[[0, i, i + 1]], shade, a))
    # Opaque first (z-buffered), then translucent (blended, no z write).
    for opaque_pass in (True, False):
        for xs, ys, zs, shade, a in tris:
            if (a >= 0.99) != opaque_pass:
                continue
            x0, x1 = max(0, int(math.floor(xs.min()))), min(pw - 1, int(math.ceil(xs.max())))
            y0, y1 = max(0, int(math.floor(ys.min()))), min(ph - 1, int(math.ceil(ys.max())))
            if x0 > x1 or y0 > y1:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            (ax, bx, cx), (ay, by, cy) = xs, ys
            den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(den) < 1e-9:
                continue
            w0 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / den
            w1 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / den
            w2 = 1 - w0 - w1
            inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
            if not inside.any():
                continue
            z = w0 * zs[0] + w1 * zs[1] + w2 * zs[2]
            zb = zbuf[y0:y1 + 1, x0:x1 + 1]
            hit = inside & (z < zb)
            if not hit.any():
                continue
            cb = color[y0:y1 + 1, x0:x1 + 1]
            ab = alpha[y0:y1 + 1, x0:x1 + 1]
            if opaque_pass:
                cb[hit] = shade
                ab[hit] = 1
                zb[hit] = z[hit]
            else:
                cb[hit] = cb[hit] * (1 - a) + shade * a
                ab[hit] = np.maximum(ab[hit], a)
    rgba = np.dstack([np.clip(color * 255, 0, 255), np.clip(alpha * 255, 0, 255)]).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def intersect(a, b):
    return (max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3]))


class Renderer:
    def __init__(self, painter, layout):
        self.painter = painter
        self.layout = layout
        self.scrolls = []

    def render_gui(self, gui, sw, sh):
        if gui.get("Enabled", True) is False:
            return
        _, _, placements = self.layout.children(gui, sw, sh)
        self.render_children(placements, 0, 0, (0, 0, sw, sh))

    def render_children(self, placements, ox, oy, clip):
        idx = {id(p[0]): i for i, p in enumerate(placements)}
        for k, x, y, w, h in sorted(placements, key=lambda p: (p[0].get("ZIndex", 1), idx[id(p[0])])):
            self.render(k, ox + x, oy + y, w, h, clip)

    def render(self, node, x, y, w, h, clip):
        if not node.visible:
            return
        p = self.painter
        # Touch targets: on phone-sized screens every tappable control is at
        # least 44x44 (TOUCH_MIN); a control pushed past its clipping parent's
        # right edge cannot be reached at all.
        if node.cls in ("TextButton", "ImageButton", "TextBox") and node.get("Active", True) is not False:
            if getattr(self, "touch", False) and (h < TOUCH_MIN - 0.5 or w < TOUCH_MIN - 0.5) and w > 0 and h > 0:
                p.issues.append(("touch-target", node.name, "%dx%d" % (round(w), round(h)), (node.get("Text") or "")[:30]))
            if x + w > clip[2] + 1 and x < clip[2] and clip[2] - clip[0] < p.w:
                p.issues.append(("clipped-x", node.name, int(x + w - clip[2]), (node.get("Text") or "")[:30]))
        p.draw_box(node, x, y, w, h, clip)
        if node.cls == "ViewportFrame":
            p.draw_viewport(node, x, y, w, h, clip)
        if node.cls in TEXT:
            p.draw_text(node, x, y, w, h, clip)
        pl, pt, pr, pb = padding(node, w, h)
        inner = clip
        if node.cls == "ScrollingFrame" or node.get("ClipsDescendants") is True:
            inner = intersect(clip, (x, y, x + w, y + h))
        if node.cls == "ScrollingFrame":
            cs = udim2(node, "CanvasSize")
            canvas_w = max(w, cs[0] * w + cs[1])
            canvas_h = cs[2] * h + cs[3]
            ew, eh, placements = self.layout.children(node, canvas_w - pl - pr, h - pt - pb)
            auto = node.get("AutomaticCanvasSize", "None")
            if "Y" in auto:
                canvas_h = max(canvas_h, eh + pt + pb)
            canvas_h = max(canvas_h, h)
            cp = node.get("CanvasPosition", [0, 0])
            self.scrolls.append((node, x, y, w, h, canvas_h, placements, pl, pt))
            self.render_children(placements, x + pl - cp[0], y + pt - cp[1], inner)
            if canvas_h > h + 1:
                thick = node.get("ScrollBarThickness", 12)
                bar = Image.new("RGBA", (max(1, int(thick * S)), max(1, int(h * h / canvas_h * S))), hex2rgb(node.get("ScrollBarImageColor3"), (255, 255, 255)) + (int(255 * (1 - (node.get("ScrollBarImageTransparency", 0) or 0))),))
                p.composite(bar, (x + w - thick) * S, y * S, clip)
            return
        _, _, placements = self.layout.children(node, w - pl - pr, h - pt - pb)
        self.render_children(placements, x + pl, y + pt, inner)


def render_shot(guis, sw, sh, art, backdrop=True):
    painter = Painter(sw, sh, art)
    if backdrop:
        painter.backdrop()
    layout = Layout()
    renderer = Renderer(painter, layout)
    renderer.touch = sh < 500
    for gui in guis:
        renderer.render_gui(gui, sw, sh)
    return painter, renderer, layout


def render_full(guis, sw, sh, art):
    """Unroll the atlas ScrollingFrame: render the page at a tall canvas."""
    painter, renderer, layout = render_shot(guis, sw, sh, art)
    target = None
    for scroll in renderer.scrolls:
        node, x, y, w, h, canvas_h, placements, pl, pt = scroll
        if canvas_h > h + 1 and (target is None or w * canvas_h > target[3] * target[5]):
            target = scroll
    if not target:
        return None, []
    node, x, y, w, h, canvas_h, placements, pl, pt = target
    tall = Painter(int(math.ceil(w)) + 16, int(math.ceil(canvas_h)) + 16, art)
    tall.img.paste((16, 39, 51, 255), (0, 0, tall.img.width, tall.img.height))
    sub = Renderer(tall, layout)
    sub.touch = sh < 500
    sub.render_children(placements, 8 + pl, 8 + pt, (0, 0, tall.w, tall.h))
    return tall, tall.issues


def finish(painter):
    return painter.img.resize((painter.img.width // S, painter.img.height // S), Image.LANCZOS).convert("RGB")


def to_nodes(raw_guis):
    out = []
    for raw in raw_guis:
        node = Node(raw)
        out.append(node)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--art", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--full", action="store_true")
    ap.add_argument("--issues", action="store_true", help="print text overflow / small text findings")
    ap.add_argument("trees", nargs="+")
    args = ap.parse_args()
    with open(args.art) as fh:
        art = json.load(fh)
    for path in args.trees:
        with open(path) as fh:
            doc = json.load(fh)
        sw, sh = doc["screen"]
        folder = os.path.join(args.out, doc["label"])
        os.makedirs(folder, exist_ok=True)
        for shot in doc["shots"]:
            guis = to_nodes(shot["guis"])
            painter, renderer, layout = render_shot(guis, sw, sh, art)
            finish(painter).save(os.path.join(folder, shot["id"] + ".png"), optimize=True)
            issues = list(painter.issues)
            if args.full:
                tall, tall_issues = render_full(to_nodes(shot["guis"]), sw, sh, art)
                if tall:
                    finish(tall).save(os.path.join(folder, shot["id"] + "-full.png"), optimize=True)
                    issues = issues + tall_issues
            if args.issues:
                seen = set()
                for issue in issues:
                    if issue in seen:
                        continue
                    seen.add(issue)
                    print(doc["label"], shot["id"], *issue, sep="\t")
            print("wrote", os.path.join(folder, shot["id"] + ".png"), file=sys.stderr)


if __name__ == "__main__":
    main()
