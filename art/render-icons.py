"""Headless contact-sheet renderer for the original OBJ masters (Pillow only).

Mirrors the UI thumbnail camera (ui.client.lua: looks from +0.7, +0.38, -1 at the
bounding-box centre, 34 degree FOV) with flat shading, so icon silhouettes can be
reviewed without Studio. Faces on the tint slot (Shade11) take a sample item colour.

    python3 art/render-icons.py art/previews/icons-sheet.png Sword:D4A84B Helm:F2C14E ...

Each NAME[:HEX] renders one cell; HEX overrides the tint colour (default: the
OBJ's "# tint" header, else silver). Shade15/Shade16 are the derived dark/light
tint shades. OBJ masters with a "# smooth N" header are Gouraud-shaded with the
same crease-angle smoothing as the server mesh forge (forge.client.lua).
A strip of 48 px copies under the sheet checks legibility at real HUD size.
Pass --cell N (and optionally --columns N, --no-strip) for larger world sheets.
"""
import math
import os
import sys

import numpy
from PIL import Image, ImageDraw, ImageFont

ART = os.path.dirname(os.path.abspath(__file__))
TINT_SHADE = "Shade11"
CELL, SMALL, SUPER = 176, 48, 3
FRAME_DIAGONAL = False
BACKGROUND, PANEL = (24, 34, 47), (31, 49, 64)


def read_palette():
    palette, name = {}, None
    with open(os.path.join(ART, "AetherPalette.mtl")) as handle:
        for line in handle:
            parts = line.split()
            if parts and parts[0] == "newmtl":
                name = parts[1]
            elif parts and parts[0] == "Kd":
                palette[name] = tuple(float(value) for value in parts[1:4])
    return palette


def read_obj(name):
    vertices, faces, material = [], [], None
    meta = {"smooth": 0.0, "tint": None}
    with open(os.path.join(ART, name + ".obj")) as handle:
        for line in handle:
            parts = line.split()
            if not parts:
                continue
            if parts[0] == "#" and len(parts) == 3 and parts[1] in ("smooth", "tint"):
                meta[parts[1]] = float(parts[2]) if parts[1] == "smooth" else parts[2]
            elif parts[0] == "v":
                vertices.append(tuple(float(value) for value in parts[1:4]))
            elif parts[0] == "usemtl":
                material = parts[1]
            elif parts[0] == "f":
                faces.append(([int(value.split("/")[0]) - 1 for value in parts[1:4]], material))
    return vertices, faces, meta


def corner_normals(vertices, faces, crease):
    """Per-corner normals: average area-weighted face normals within the crease angle."""
    face_normals, areas, around = [], [], {}
    for index, (ids, _) in enumerate(faces):
        points = [vertices[i] for i in ids]
        raw = cross(sub(points[1], points[0]), sub(points[2], points[0]))
        areas.append(math.sqrt(dot(raw, raw)))
        face_normals.append(unit(raw))
        for i in ids:
            around.setdefault(i, []).append(index)
    limit = math.cos(math.radians(crease))
    result = []
    for index, (ids, _) in enumerate(faces):
        normal = face_normals[index]
        if crease <= 0:
            result.append([normal] * 3)
            continue
        corners = []
        for i in ids:
            total = (0.0, 0.0, 0.0)
            for other in around[i]:
                if dot(face_normals[other], normal) >= limit:
                    n, w = face_normals[other], areas[other]
                    total = (total[0] + n[0] * w, total[1] + n[1] * w, total[2] + n[2] * w)
            corners.append(unit(total))
        result.append(corners)
    return result


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def unit(a):
    length = math.sqrt(dot(a, a)) or 1
    return (a[0] / length, a[1] / length, a[2] / length)


def tint_shades(tint):
    dark = tuple(channel * 0.62 for channel in tint)
    light = tuple(channel + (1 - channel) * 0.4 for channel in tint)
    return {TINT_SHADE: tint, "Shade15": dark, "Shade16": light}


def render(name, tint, size):
    palette = read_palette()
    vertices, faces, meta = read_obj(name)
    if tint is None and meta["tint"]:
        tint = tuple(int(meta["tint"][i:i + 2], 16) / 255 for i in (0, 2, 4))
    shades = tint_shades(tint) if tint else {}
    normals = corner_normals(vertices, faces, meta["smooth"])
    low = [min(v[i] for v in vertices) for i in range(3)]
    high = [max(v[i] for v in vertices) for i in range(3)]
    centre = tuple((low[i] + high[i]) / 2 for i in range(3))
    radius = max(high[i] - low[i] for i in range(3))
    if FRAME_DIAGONAL:
        radius = max(radius, 0.8 * math.sqrt(sum((high[i] - low[i]) ** 2 for i in range(3))))
    forward_dir = unit((0.7, 0.38, -1))
    eye = tuple(centre[i] + forward_dir[i] * radius * 2 for i in range(3))
    forward = unit(sub(centre, eye))
    right = unit(cross(forward, (0, 1, 0)))
    up = cross(right, forward)
    focal = 1 / math.tan(math.radians(34) / 2)
    light = unit((1, 1, 2))  # Roblox LightDirection (-1,-1,-2) points from the light.
    scale = size * SUPER
    pixels = numpy.empty((scale, scale, 3), dtype=numpy.uint8)
    pixels[:] = PANEL
    zbuffer = numpy.full((scale, scale), numpy.inf)
    for (ids, material), corners in zip(faces, normals):
        points = [vertices[i] for i in ids]
        normal = unit(cross(sub(points[1], points[0]), sub(points[2], points[0])))
        middle = tuple(sum(p[i] for p in points) / 3 for i in range(3))
        flip = dot(normal, sub(eye, middle)) < 0  # double-sided preview
        base = shades.get(material) or palette[material]
        colour = []
        for corner in corners:
            if flip:
                corner = (-corner[0], -corner[1], -corner[2])
            shade = 0.55 + 0.5 * max(0.0, dot(corner, light))
            colour.append(tuple(min(255.0, channel * 255 * shade) for channel in base))
        projected = []
        for point in points:
            relative = sub(point, eye)
            depth = dot(relative, forward)
            projected.append((
                scale / 2 + dot(relative, right) / depth * focal * scale / 2,
                scale / 2 - dot(relative, up) / depth * focal * scale / 2,
                depth,
            ))
        rasterise(pixels, zbuffer, projected, colour)
    return Image.fromarray(pixels).resize((size, size), Image.LANCZOS)


def rasterise(pixels, zbuffer, points, colour):
    (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = points
    area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
    if abs(area) < 1e-9:
        return
    height, width = zbuffer.shape
    left, right = max(int(min(x0, x1, x2)), 0), min(int(max(x0, x1, x2)) + 1, width)
    top, bottom = max(int(min(y0, y1, y2)), 0), min(int(max(y0, y1, y2)) + 1, height)
    if left >= right or top >= bottom:
        return
    xs, ys = numpy.meshgrid(numpy.arange(left, right) + 0.5, numpy.arange(top, bottom) + 0.5)
    w0 = ((x1 - xs) * (y2 - ys) - (x2 - xs) * (y1 - ys)) / area
    w1 = ((x2 - xs) * (y0 - ys) - (x0 - xs) * (y2 - ys)) / area
    w2 = 1 - w0 - w1
    inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
    depth = w0 * z0 + w1 * z1 + w2 * z2
    window = zbuffer[top:bottom, left:right]
    visible = inside & (depth < window)
    window[visible] = depth[visible]
    c0, c1, c2 = (numpy.array(c) for c in colour)
    shaded = w0[..., None] * c0 + w1[..., None] * c1 + w2[..., None] * c2
    pixels[top:bottom, left:right][visible] = numpy.clip(shaded[visible], 0, 255).astype(numpy.uint8)


def main():
    global CELL, FRAME_DIAGONAL
    args = sys.argv[1:]
    columns_override, strip = None, True
    while args and args[0].startswith("--"):
        flag = args.pop(0)
        if flag == "--cell":
            CELL = int(args.pop(0))
        elif flag == "--columns":
            columns_override = int(args.pop(0))
        elif flag == "--no-strip":
            strip = False
        elif flag == "--fit-diagonal":
            FRAME_DIAGONAL = True
    output, specs = args[0], args[1:]
    cells = []
    for spec in specs:
        name, _, hex_colour = spec.partition(":")
        tint = tuple(int(hex_colour[i:i + 2], 16) / 255 for i in (0, 2, 4)) if hex_colour else None
        cells.append((name, tint))
    columns = min(columns_override or 6, len(cells))
    rows = math.ceil(len(cells) / columns)
    strip_width = len(cells) * (SMALL + 4) + 12 if strip else 0
    sheet = Image.new("RGB", (max(columns * (CELL + 8) + 8, strip_width), rows * (CELL + 26) + 8 + (SMALL + 16 if strip else 0)), BACKGROUND)
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for index, (name, tint) in enumerate(cells):
        x, y = 8 + index % columns * (CELL + 8), 8 + index // columns * (CELL + 26)
        sheet.paste(render(name, tint, CELL), (x, y))
        draw.text((x + 4, y + CELL + 6), name, fill=(220, 230, 235), font=font)
        if strip:
            sheet.paste(render(name, tint, SMALL), (8 + index * (SMALL + 4), rows * (CELL + 26) + 12))
    sheet.save(output)
    print("Rendered", len(cells), "icons to", output)


if __name__ == "__main__":
    main()
