"""2D-окружение трасс: из листов ИИ-художника (art/env_<трасса>/) делает
атласы для игры и таблицу кусков.

  ground.*  -> assets/env/<трасса>/ground.png    бесшовная земля (как есть)
  <лист>.*  -> assets/env/<трасса>/<лист>.png    вырезанные куски, переупакованы

Фон листов — сплошной цвет-ключ (маджента у «Травы», зелёный у «Ночного
города», где маджента — цвет неона). Прозрачность считается по «силе
ключа» (для маджента min(R, B) - G, для зелёного G - max(R, B)), с краёв
снимается ореол ключевого цвета (despill), кромка съедается на 1 px.
Кусок = связные компоненты маски, чей центр лежит в его ячейке сетки (по
рамке клетки резать нельзя — объекты на листах вылезают за свою клетку);
куски переупаковываются в атлас без соседей.
Таблица пишется в scripts/Env<Трасса>Atlas.gd (генерируется, руками не
править — правится TRACKS здесь).

Запуск: python tools/gen_env.py [grass|neon]   (без аргумента — все)
"""
import glob
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

# Трасса -> ключ фона и листы. Лист: (сетка, плоский, без освещения, куски).
# Кусок: (имя, размер в метрах) — у стоячих картонок размер — высота на
# экране, у плоских — ширина; "" — ячейку не брать. Размеры подобраны на
# глаз относительно машины ~4 м.
TRACKS = {
    "grass": {
        "key": "magenta",
        "sheets": {
            "patches": (3, True, False, [
                ("mud_pit", 30), ("moto_loop", 36), ("pit_pad", 30),
                ("fuel_station", 30), ("service_yard", 30), ("car_park", 34),
                ("stubble", 36), ("pond", 32), ("crossroads", 34),
            ]),
            "nature": (4, False, False, [
                ("birch", 9), ("birch_pair", 9), ("oak", 10), ("apple", 7),
                ("spruce", 11), ("poplars", 12), ("bush", 3.5), ("dry_shrub", 3),
                ("weeds", 2.5), ("haystack", 4.5), ("bales", 3), ("power_pole", 8),
                ("water_pump", 2), ("fence", 2), ("gate", 2), ("sunflowers", 2.5),
            ]),
            "race": (4, False, False, [
                ("stand_front", 8), ("stand_back", 8), ("tower", 10), ("tent", 5.5),
                ("shed", 5.5), ("tyre_wall", 3), ("tyre_pile", 2), ("cones", 1.5),
                ("flag", 5), ("billboard_front", 6.5), ("billboard_back", 6.5),
                ("floodlight", 12), ("fuel_pump", 2.5), ("jerrycans", 2),
                ("crates", 2.2), ("", 0),   # сгоревший остов — не берём
            ]),
        },
    },
    # Ночной город: картонки нарисованы уже ночными (окна и неон светятся
    # в самой картинке) — показываются без освещения сцены. Земля и
    # плоские куски освещены как земля.
    "neon": {
        "key": "green",
        "sheets": {
            "patches": (3, True, False, [
                ("car_meet", 32), ("drift_spot", 30), ("gas_station", 30),
                ("garage_yard", 30), ("port_yard", 34), ("plaza", 34),
                ("intersection", 34), ("roof_deck", 32), ("skate_plaza", 30),
            ]),
            "decals": (4, True, False, [
                ("", 0), ("", 0), ("", 0),   # следы шин зелёные, дым — мимо
                ("puddle_cyan", 4), ("puddle_pink", 4), ("puddle_orange", 4),
                ("oil_slick", 3.5), ("pool_orange", 6), ("pool_blue", 6),
                ("pool_violet", 6), ("manhole", 1.6), ("grate", 1.6),
                ("crosswalk", 5), ("start_line", 6), ("nitro_mark", 3),
                ("", 0),   # стекло зелёное — съедается ключом
            ]),
            "buildings": (4, False, True, [
                ("tower_cyan", 24), ("tower_slim", 26), ("office_curved", 13),
                ("tower_round", 22), ("tuning_shop", 9), ("car_wash", 8),
                ("diner", 7.5), ("nightclub", 10), ("car_park", 12),
                ("screen_store", 10), ("showroom", 9), ("corner_store", 8),
                ("hotel", 16), ("billboard_big", 9), ("skybridge", 12),
                ("mast", 20),
            ]),
            "street": (4, False, True, [
                ("lamp", 6), ("lamp_double", 6), ("traffic_red", 4.5),
                ("traffic_yellow", 4.5), ("bus_stop", 3.5), ("", 0),   # будка — британская
                ("vending", 2.4), ("billboard_front", 6.5),
                ("billboard_back", 6.5), ("neon_arrow", 4.5), ("power_pole", 8),
                ("barrier", 2), ("cones", 1.5), ("bench_bin", 1.8),
                ("taxi", 2.6), ("bus", 4.2),
            ]),
        },
    },
}

KEY_LO = 40.0    # сила ключа, ниже которой пиксель непрозрачен
KEY_HI = 170.0   # сила ключа, выше которой пиксель — фон
PAD = 4          # зазор между кусками в атласе, px (против протечки мипмапов)
ATLAS_W = 1280   # ширина собранного атласа, px
MIN_AREA = 25    # компоненты меньше — соринки, не объект


def key_out(img: Image.Image, key: str) -> np.ndarray:
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    if key == "magenta":
        m = np.minimum(r, b) - g
    else:
        m = g - np.maximum(r, b)
    alpha = 1.0 - np.clip((m - KEY_LO) / (KEY_HI - KEY_LO), 0.0, 1.0)
    # Despill: убираем составляющую ключевого цвета у полупрозрачной
    # кромки и у пикселей с отсветом фона.
    spill = np.clip(m, 0.0, None)
    if key == "magenta":
        r, b = r - spill, b - spill
    else:
        g = g - spill
    # Кромку съедаем на 1 px: в ней остаётся смесь с фоном, которую despill
    # превращает в цветной ореол.
    a8 = Image.fromarray((alpha * 255.0).astype(np.uint8), "L")
    alpha = np.asarray(a8.filter(ImageFilter.MinFilter(3))).astype(np.float32) / 255.0
    out = np.dstack([r, g, b, alpha * 255.0])
    out[alpha <= 0.0, :3] = 0.0
    return np.clip(out, 0, 255).astype(np.uint8)


def cut(rgba: np.ndarray, grid: int, items: list) -> list:
    """[(имя, размер, RGBA-вырезка)] — пиксели соседей в вырезку не попадают."""
    h, w = rgba.shape[:2]
    mask = rgba[..., 3] > 128
    # Склейка через 1 px: соседние объекты на листе почти касаются друг
    # друга, отлетевшие части (провода, травинки) идут в ячейку по центру.
    near = ndimage.binary_dilation(mask, iterations=1)
    labels, n = ndimage.label(near)
    labels[~mask] = 0
    found = ndimage.find_objects(labels)
    owner = {}   # метка -> индекс ячейки
    for lab in range(1, n + 1):
        sl = found[lab - 1]
        if sl is None or int((labels[sl] == lab).sum()) < MIN_AREA:
            continue
        cy, cx = ndimage.center_of_mass(labels == lab)
        owner[lab] = int(cy * grid / h) * grid + int(cx * grid / w)
    out = []
    for i, (name, size) in enumerate(items):
        if not name:
            continue
        labs = [lab for lab, cell in owner.items() if cell == i]
        if not labs:
            raise SystemExit(f"пустая ячейка {name}")
        own = np.isin(labels, labs)
        ys, xs = np.nonzero(own)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        piece = rgba[y0:y1, x0:x1].copy()
        piece[~own[y0:y1, x0:x1]] = 0
        out.append((name, size, piece))
    return out


def pack(pieces: list) -> tuple:
    """Полочная упаковка по убыванию высоты. -> (атлас, [(имя, x, y, w, h, размер)])"""
    order = sorted(pieces, key=lambda p: -p[2].shape[0])
    x = y = shelf = PAD
    placed = []
    for name, size, img in order:
        ph, pw = img.shape[:2]
        if x + pw + PAD > ATLAS_W:
            x, y = PAD, y + shelf + PAD
            shelf = 0
        placed.append((name, x, y, pw, ph, size, img))
        x += pw + PAD
        shelf = max(shelf, ph)
    atlas = np.zeros((y + shelf + PAD, ATLAS_W, 4), np.uint8)
    for name, x, y, pw, ph, size, img in placed:
        atlas[y:y + ph, x:x + pw] = img
    names = [p[0] for p in pieces]
    rects = sorted(((n, x, y, pw, ph, s) for n, x, y, pw, ph, s, _ in placed),
            key=lambda r: names.index(r[0]))
    return atlas, rects


def source(src: str, stem: str) -> str:
    found = sorted(glob.glob(os.path.join(src, stem + ".*")))
    if not found:
        raise SystemExit(f"нет исходника {src}/{stem}.*")
    return found[0]


def build(track: str) -> None:
    cfg = TRACKS[track]
    src = os.path.join(ROOT, "art", "env_" + track)
    dst = os.path.join(ROOT, "assets", "env", track)
    res = "res://assets/env/%s/" % track
    os.makedirs(dst, exist_ok=True)
    Image.open(source(src, "ground")).convert("RGB").save(
            os.path.join(dst, "ground.png"))
    title = track.capitalize()
    lines = [
        "extends RefCounted",
        "## СГЕНЕРИРОВАНО tools/gen_env.py — руками не править.",
        f"## Куски атласов 2D-окружения трассы «{track}»:",
        "## имя -> [x, y, ширина, высота в px атласа, размер в метрах].",
        "## У картонок размер — высота на экране, у плоских кусков — ширина.",
        "",
        f'const GROUND := "{res}ground.png"',
        "",
    ]
    table = []
    for sheet, (grid, flat, unshaded, items) in cfg["sheets"].items():
        rgba = key_out(Image.open(source(src, sheet)), cfg["key"])
        atlas, rects = pack(cut(rgba, grid, items))
        Image.fromarray(atlas, "RGBA").save(os.path.join(dst, sheet + ".png"))
        lines.append(f"const {sheet.upper()} := {{")
        for name, x, y, w, h, size in rects:
            lines.append(f'\t"{name}": [{x}, {y}, {w}, {h}, {float(size)}],')
        lines.append("}")
        lines.append("")
        table.append(f'\t"{sheet}": ["{res}{sheet}.png", {sheet.upper()}, '
                f"{str(flat).lower()}, {str(unshaded).lower()}],")
        print(track, sheet, len(rects), "pieces, atlas",
                atlas.shape[1], "x", atlas.shape[0])
    lines.append("## Лист -> [атлас, куски, плоский (лежит на земле), без освещения].")
    lines.append("const SHEETS := {")
    lines += table
    lines.append("}")
    lines.append("")
    path = os.path.join(ROOT, "scripts", f"Env{title}Atlas.gd")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print("->", os.path.relpath(path, ROOT))


for t in (sys.argv[1:] or list(TRACKS)):
    build(t)
