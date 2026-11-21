"""Approximate offline previews of §28 signs (Pillow + numpy; not Roblox captures).

    lune run tools/dump-signs.luau build/signs.json "Artisans' Row" "Starforge" ...
    python3 tools/render-signs.py build/signs.json docs/screenshots/signs-preview.png [--night]

Each sign's parts are laid out exactly as forge.client.lua would (fit boxes,
declared ShapeBox, ShapeFit Uniform) from the OBJ masters, flat/Gouraud shaded
like art/render-icons.py, and the Front SurfaceGui is painted from the dumped
GUI tree and perspective-warped onto the board. Fonts are stand-ins (DejaVu
Serif Bold for Merriweather/Fondamento, Inter Bold for BuilderSans), so glyph
widths are wider than Roblox's: text that fits here fits in Studio.
"""
import importlib.util
import json
import math
import os
import re
import sys

import numpy
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("icons", os.path.join(ROOT, "art", "render-icons.py"))
icons = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icons)
SERIF = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
SANS = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"
CELL, SUPER = 560, 2

WORLD = open(os.path.join(ROOT, "art", "WorldCatalog.lua")).read()


def fit_of(shape):
    match = re.search(r"shapes\." + shape + r'=unpack\("[^"]*","[^"]*",(\{.*?\})\)\n', WORLD)
    if not match:
        return None
    fit = re.search(r"fit=\{\{([^}]*)\},\{([^}]*)\}\}", match.group(1))
    if not fit:
        return None
    return [float(x) for x in fit.group(1).split(",")], [float(x) for x in fit.group(2).split(",")]


def hexrgb(value):
    return tuple(int(value[i:i + 2], 16) / 255 for i in (0, 2, 4))


def vadd(*vs):
    return tuple(sum(v[i] for v in vs) for i in range(3))


def vmul(v, k):
    return tuple(c * k for c in v)


def place(part):
    """World triangles for one part: (points, material colour) list."""
    palette = icons.read_palette()
    shape = part.get("shape")
    right, up, back = part["right"], part["up"], part["back"]
    centre = part["pos"]
    box = part.get("box") or part["size"]
    if part.get("offset"):
        o = part["offset"]
        centre = vadd(centre, vmul(right, o[0]), vmul(up, o[1]), vmul(back, o[2]))
    path = os.path.join(ROOT, "art", (shape or "") + ".obj")
    tris = []
    if shape and os.path.exists(path):
        vertices, faces, meta = icons.read_obj(shape)
        tint = hexrgb(part["tint"]) if part.get("tint") else (hexrgb(meta["tint"]) if meta["tint"] else None)
        shades = icons.tint_shades(tint) if tint else {}
        lo = [min(v[i] for v in vertices) for i in range(3)]
        hi = [max(v[i] for v in vertices) for i in range(3)]
        fit = fit_of(shape) or (lo, hi)
        fsize = [max(fit[1][i] - fit[0][i], .01) for i in range(3)]
        fc = [(fit[0][i] + fit[1][i]) / 2 for i in range(3)]
        k = [box[i] / fsize[i] for i in range(3)]
        lift = 0
        if part.get("fit") == "Uniform":
            m = min(k)
            k = [m, m, m]
            lift = (fsize[1] * m - box[1]) / 2
        normals = icons.corner_normals(vertices, faces, meta["smooth"])

        def world(v):
            x, y, z = ((v[i] - fc[i]) * k[i] for i in range(3))
            return vadd(centre, vmul(right, x), vmul(up, y + lift), vmul(back, z))
        for (ids, material), corner in zip(faces, normals):
            base = shades.get(material) or palette[material]
            wn = [vadd(vmul(right, n[0]), vmul(up, n[1]), vmul(back, n[2])) for n in corner]
            tris.append(([world(vertices[i]) for i in ids], base, wn))
    else:
        base = hexrgb(part["color"])
        s = [c / 2 for c in part["size"]]
        corners = {}
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    corners[(sx, sy, sz)] = vadd(part["pos"], vmul(right, sx * s[0]), vmul(up, sy * s[1]), vmul(back, sz * s[2]))
        for axis in range(3):
            for sign in (-1, 1):
                quad = []
                for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                    key = [0, 0, 0]
                    key[axis] = sign
                    others = [i for i in range(3) if i != axis]
                    key[others[0]], key[others[1]] = a, b
                    quad.append(corners[tuple(key)])
                n = [right, up, back][axis]
                n = vmul(n, sign)
                tris.append(([quad[0], quad[1], quad[2]], base, [n] * 3))
                tris.append(([quad[0], quad[2], quad[3]], base, [n] * 3))
    return tris


def paint(gui, w_studs, h_studs, scale):
    pps = gui["pps"]
    cw, ch = int(w_studs * pps * scale), int(h_studs * pps * scale)
    img = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    items = sorted(gui["items"], key=lambda i: i["z"])
    for it in items:
        x, y = it["x"] * scale, it["y"] * scale
        w = cw if it["w"] == -1 else it["w"] * scale
        h = ch if it["h"] == -1 else it["h"] * scale
        if it["class"] == "Frame":
            colour = tuple(int(c * 255) for c in hexrgb(it["bg"]))
            alpha = int(255 * (1 - it["bgT"]))
            if it["rot"]:
                cx, cy, r = x + w / 2, y + h / 2, w / 2 * math.sqrt(2)
                pts = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
                if alpha:
                    draw.polygon(pts, fill=colour + (alpha,))
                if it.get("stroke"):
                    sc = tuple(int(c * 255) for c in hexrgb(it["stroke"][0]))
                    draw.line(pts + [pts[0]], fill=sc + (255,), width=max(1, int(it["stroke"][1] * scale)))
            else:
                if alpha:
                    if it["name"] == "Panel":
                        top = tuple(min(255, int(c + (249 - c) * .1)) for c in colour)
                        bottom = tuple(int(c * .7) for c in colour)
                        for row in range(int(h)):
                            t = row / max(1, h - 1)
                            draw.line([(x, y + row), (x + w, y + row)], fill=tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3)) + (alpha,))
                    else:
                        draw.rectangle([x, y, x + w, y + h], fill=colour + (alpha,))
                if it.get("stroke"):
                    sc = tuple(int(c * 255) for c in hexrgb(it["stroke"][0]))
                    draw.rectangle([x, y, x + w, y + h], outline=sc + (int(255 * (1 - it["stroke"][2])),), width=max(1, int(it["stroke"][1] * scale)))
        elif it.get("text"):
            font = ImageFont.truetype(SANS if "BuilderSans" in it["font"] else SERIF, max(6, int(it["size"] * scale * .92)))
            words, lines, line = it["text"].split(), [], ""
            for word in words:
                cand = (line + " " + word).strip()
                if line and draw.textlength(cand, font=font) > w:
                    lines.append(line)
                    line = word
                else:
                    line = cand
            lines.append(line)
            lh = it["size"] * scale * 1.15
            ty = y + (h - lh * len(lines)) / 2
            colour = tuple(int(c * 255) for c in hexrgb(it["color"])) + (int(255 * (1 - it["tT"])),)
            stroke = it.get("stroke")
            for row, text in enumerate(lines):
                tw = draw.textlength(text, font=font)
                tx = x if it["align"] == "Left" else (x + w - tw if it["align"] == "Right" else x + (w - tw) / 2)
                kwargs = {}
                if stroke:
                    kwargs = {"stroke_width": max(1, int(stroke[1] * scale * .6)), "stroke_fill": tuple(int(c * 255) for c in hexrgb(stroke[0]))}
                draw.text((tx, ty + row * lh), text, font=font, fill=colour, **kwargs)
    return img


def perspective_coeffs(src, dst):
    rows = []
    for (x, y), (u, v) in zip(dst, src):
        rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        rows.append([0, 0, 0, x, y, 1, -v * x, -v * y])
    a = numpy.array(rows, dtype=float)
    b = numpy.array([c for p in src for c in p], dtype=float)
    return numpy.linalg.solve(a, b).tolist()


def render_sign(sign, night):
    tris = []
    for part in sign["parts"]:
        tris += place(part)
    pts = [p for t in tris for p in t[0]]
    lo = [min(p[i] for p in pts) for i in range(3)]
    hi = [max(p[i] for p in pts) for i in range(3)]
    centre = tuple((lo[i] + hi[i]) / 2 for i in range(3))
    radius = max(hi[i] - lo[i] for i in range(3))
    main = next(p for p in sign["parts"] if p.get("guis"))
    look = vmul(main["back"], -1)
    direction = icons.unit(vadd(look, vmul(main["right"], -.32), (0, .22, 0)))
    eye = vadd(centre, vmul(direction, radius * 1.75))
    forward = icons.unit(icons.sub(centre, eye))
    right = icons.unit(icons.cross(forward, (0, 1, 0)))
    up = icons.cross(right, forward)
    focal = 1 / math.tan(math.radians(34) / 2)
    light = icons.unit((1, 1, 2))
    scale = CELL * SUPER
    sky = (16, 22, 40) if night else (150, 190, 220)
    pixels = numpy.empty((scale, scale, 3), dtype=numpy.uint8)
    pixels[:] = sky
    zbuffer = numpy.full((scale, scale), numpy.inf)
    ambient, diffuse = (.22, .25) if night else (.55, .5)

    def project(point):
        rel = icons.sub(point, eye)
        depth = icons.dot(rel, forward)
        return (scale / 2 + icons.dot(rel, right) / depth * focal * scale / 2, scale / 2 - icons.dot(rel, up) / depth * focal * scale / 2, depth)
    for points, base, normals in tris:
        normal = icons.unit(icons.cross(icons.sub(points[1], points[0]), icons.sub(points[2], points[0])))
        middle = tuple(sum(p[i] for p in points) / 3 for i in range(3))
        flip = icons.dot(normal, icons.sub(eye, middle)) < 0
        colour = []
        for n in normals:
            if flip:
                n = vmul(n, -1)
            shade = ambient + diffuse * max(0.0, icons.dot(n, light))
            colour.append(tuple(min(255.0, c * 255 * shade) for c in base))
        icons.rasterise(pixels, zbuffer, [project(p) for p in points], colour)
    image = Image.fromarray(pixels).convert("RGBA")
    for part in sign["parts"]:
        if not part.get("guis"):
            continue
        w, h, d = part["size"]
        r, u, b = part["right"], part["up"], part["back"]
        # Draw the face the camera sees: Front (-Z, GUI +x along -Right) or Back.
        front = icons.dot(icons.sub(eye, part["pos"]), b) < 0
        gui = next((g for g in part["guis"] if g["face"] == ("Front" if front else "Back")), None)
        if not gui:
            continue
        s = -1 if front else 1
        face = vadd(part["pos"], vmul(b, s * (d / 2 + .01)))
        corners = [vadd(face, vmul(r, -s * w / 2), vmul(u, h / 2)), vadd(face, vmul(r, s * w / 2), vmul(u, h / 2)),
                   vadd(face, vmul(r, s * w / 2), vmul(u, -h / 2)), vadd(face, vmul(r, -s * w / 2), vmul(u, -h / 2))]
        dst = [project(c)[:2] for c in corners]
        art = paint(gui, w, h, 3)
        if night:
            # LightInfluence 0.25: the face stays ~80% self-lit after dusk.
            art = Image.merge("RGBA", [*(ch.point(lambda v: int(v * .82)) for ch in art.split()[:3]), art.split()[3]])
        src = [(0, 0), (art.width, 0), (art.width, art.height), (0, art.height)]
        warped = art.transform((scale, scale), Image.PERSPECTIVE, perspective_coeffs(src, dst), Image.BICUBIC)
        image.alpha_composite(warped)
    return image.convert("RGB").resize((CELL, CELL), Image.LANCZOS)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    night = "--night" in sys.argv
    signs = json.load(open(args[0]))
    columns = min(3, len(signs))
    rows = math.ceil(len(signs) / columns)
    sheet = Image.new("RGB", (columns * (CELL + 8) + 8, rows * (CELL + 28) + 8), (24, 34, 47))
    draw = ImageDraw.Draw(sheet)
    label = ImageFont.truetype(SANS, 15)
    for i, sign in enumerate(signs):
        x, y = 8 + i % columns * (CELL + 8), 8 + i // columns * (CELL + 28)
        sheet.paste(render_sign(sign, night), (x, y))
        draw.text((x + 4, y + CELL + 5), f"{sign['title']}  ({sign['kind']})", fill=(220, 230, 235), font=label)
    sheet.save(args[1])
    print(f"Rendered {len(signs)} signs to {args[1]}")


if __name__ == "__main__":
    main()
