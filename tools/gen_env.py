"""2D-окружение трасс: из листов ИИ-художника (art/env_<трасса>/) делает
атласы для игры и таблицу кусков.

  ground.*  -> assets/env/<трасса>/ground.png    бесшовная земля (как есть)
  road.*    -> assets/env/<трасса>/road.png      полотно (road_texture), если "road"
  <лист>.*  -> assets/env/<трасса>/<лист>.png    вырезанные куски, переупакованы

Фон листов — сплошной цвет-ключ (маджента у «Травы», зелёный у «Ночного
города», где маджента — цвет неона; чёрный у космоса — там куски кладутся
сложением цвета и режутся по ячейкам, cut_add). Прозрачность считается по «силе
ключа» (для маджента min(R, B) - G, для зелёного G - max(R, B)), с краёв
снимается ореол ключевого цвета (despill), кромка съедается на 1 px.
Кусок = связные компоненты маски, чей центр лежит в его ячейке сетки (по
рамке клетки резать нельзя — объекты на листах вылезают за свою клетку);
куски переупаковываются в атлас без соседей.
Таблица пишется в scripts/Env<Трасса>Atlas.gd (генерируется, руками не
править — правится TRACKS здесь).

Запуск: py -3 tools/gen_env.py [grass|neon|snow|space]   (без аргумента — все)
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
    # «Трава» с 23.10 — дешёвый стадионный трек (как местные стоковые
    # гонки), а не гонка в деревне: прежние листы patches/nature/race —
    # в art/env_grass/unused. Земля — перекраска прежней в зелень
    # (tools/recolor_grass_ground.py). Ячейки "" — надписи, вещи с
    # направлением (заборы, стенки, живая изгородь легли бы поперёк
    # трассы) и странное (бокс без пола).
    "grass": {
        "key": "magenta",
        "road": True,
        "sheets": {
            "stadium": (4, False, False, [
                ("stand_front", 6), ("stand_back", 6), ("stand_covered", 6.5),
                ("control_tower", 9), ("leaderboard", 7), ("", 0), ("", 0),
                ("light_tower", 12), ("billboard_front", 6.5),
                ("billboard_back", 6.5), ("flagman", 3.2), ("ticket_booth", 4.2),
                ("concession", 4.5), ("merch_trailer", 3.8), ("toilets", 3),
                ("arch", 5),
            ]),
            # Фон у листа тусклый (199, 63, 135) и с линиями сетки — ключ
            # подстраивается под фон (key_out), линии уходят вместе с ним.
            "pit": (4, False, False, [
                ("garages", 6.5), ("", 0), ("crew_red", 2.4), ("crew_blue", 2.2),
                ("transporter", 5), ("hauler", 4), ("pickup_trailer", 2.8),
                ("motorhome", 4.5), ("pace_car", 2.4), ("safety_truck", 2.6),
                ("tow_truck", 3.8), ("fuel_cart", 2), ("tyre_stack", 2),
                ("tyre_wall", 2), ("canopy", 3.6), ("", 0),   # луч фонаря — розовая дымка
            ]),
            "infield": (4, False, False, [
                ("camper", 4.2), ("fans_pickup", 3.6), ("picnic_tent", 3.8),
                ("tent", 2.4), ("parked_cars", 2.6), ("banners", 5),
                ("tyre_balloon", 5), ("topiary", 4), ("poplars", 7.5), ("", 0),
                ("bush", 2.2), ("", 0), ("", 0), ("arrow_sign", 3),
                ("medic_tent", 3), ("helipad", 4),
            ]),
        },
    },
    # Ночной город: картонки нарисованы уже ночными (окна и неон светятся
    # в самой картинке) — показываются без освещения сцены. Земля и
    # плоские куски освещены как земля.
    "neon": {
        "key": "green",
        "road": True,
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
            # Вторая волна домов (23.10). "" — вывески с надписями (HOTEL,
            # LAUNDROMAT, 24 HOUR, TYRE SHOP…).
            "buildings_tall": (4, False, True, [
                ("tower_stepped", 26), ("tower_twisted", 26),
                ("tower_checker", 24), ("tower_helipad", 24), ("office_l", 13),
                ("", 0), ("twin_towers", 26), ("tower_cylinder", 22),
                ("tower_crane", 22), ("bank", 11), ("glass_cube", 14),
                ("tower_screen", 24), ("tower_glassroof", 22),
                ("center_curved", 13), ("residential_tall", 22), ("tv_tower", 28),
            ]),
            "buildings_mid": (4, False, True, [
                ("brick_fire", 14), ("corner_glass", 14), ("townhouses", 11),
                ("balconies", 14), ("lofts", 13), ("gym", 13),
                ("office_violet", 14), ("roof_frame", 15), ("roof_billboard", 15),
                ("", 0), ("pharmacy", 14), ("parking_deck", 9), ("motel", 8),
                ("pizza", 13), ("mural", 15), ("", 0),
            ]),
            # Низкие (1–2 этажа) — для ближней к камере стороны улицы.
            "buildings_low": (4, False, True, [
                ("garage_low", 7), ("", 0), ("burger", 7), ("", 0),
                ("", 0), ("club_low", 8), ("", 0), ("warehouse_low", 7),
                ("gas_shop", 7), ("", 0), ("workshop_low", 7), ("shops_row", 7.5),
                ("carwash_low", 7), ("parking_booth", 5), ("bar_low", 7),
                ("substation", 6),
            ]),
        },
    },
    # Зима (23.10): природа и деревня в 2D; трибуны, старт и обочинные
    # пропсы пока 3D. Из мелочи у обочин взяты только сугробы и лёд — у
    # остальных своя подложка-плита с бортиком (легла бы заплаткой).
    # Полотно не взято: unused/road_directional.jpg — нарисована полоса
    # дороги с белыми краями и косыми ледяными руслами.
    "snow": {
        "key": "magenta",
        # Гранёные сугробы земли на полном контрасте читались ледяными
        # глыбами — приглушены вдвое.
        "ground_contrast": 0.5,
        "sheets": {
            "nature": (4, False, False, [
                ("spruce_tall", 9), ("fir_small", 5), ("fir_group", 9),
                ("birch_frost", 7.5), ("oak_bare", 8), ("bush_snow", 3.5),
                ("rowan", 6), ("boulder", 3), ("rocks", 3), ("stump_ice", 2.6),
                ("snowman", 3.2), ("snow_fort", 2.8), ("drift", 3),
                ("firewood", 2.6), ("", 0), ("pump_frozen", 3),
            ]),
            "village": (4, False, False, [
                ("cabin", 7), ("cottage", 7), ("lodge", 8.5), ("log_hut", 6.5),
                ("barn", 7.5), ("garage_snow", 6), ("", 0),   # CAFE
                ("", 0),   # остановка с фиолетовым стеклом — съест ключ
                ("xmas_tree", 6.5), ("well", 4.2), ("logs", 2.4), ("sleigh", 2.6),
                ("jeep", 3), ("water_tower", 7.5), ("ski_rack", 3), ("rink", 3.2),
            ]),
            "decals": (4, True, False, [
                ("", 0), ("", 0), ("", 0), ("", 0), ("", 0),
                ("drift_ridge", 6), ("snow_pile", 3), ("", 0),
                ("", 0), ("", 0), ("", 0), ("", 0),
                ("", 0), ("ice_pieces", 3), ("", 0), ("", 0),
            ]),
        },
    },
    # Космос (23.10): земля — звёздное поле с туманностями вместо печёного
    # кодом; туманности и галактики — плоские куски на пустоте, кладутся
    # сложением цвета (чёрное = ничего). Ячейки со своим квадратным фоном
    # (скопление, галактика с ребра) не взяты.
    "space": {
        "key": "black",
        "sheets": {
            "nebulae": (3, True, True, [
                ("galaxy_spiral", 34), ("nebula_pink", 44), ("nebula_blue", 44),
                ("", 0), ("filament", 40), ("", 0),
                ("nebula_orange", 30), ("starburst", 30), ("ring", 28),
            ], "add"),
        },
    },
}

KEY_LO = 40.0    # сила ключа, ниже которой пиксель непрозрачен
KEY_HI = 170.0   # сила ключа, выше которой пиксель — фон
# У листа с тусклым фоном пороги — доли силы ключа самого фона (медиана по
# рамке листа); у чистого фона остаются прежние KEY_LO/KEY_HI. Доля HI
# такая, чтобы ушли и нарисованные тени (тот же цвет, темнее, ~0.8 фона).
KEY_LO_K = 0.35
KEY_HI_K = 0.75
ADD_FLOOR = 6.0  # чёрный jpeg — не ноль: вычитаем, чтобы сложение не светило квадратом
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
    frame = np.concatenate([m[:6].ravel(), m[-6:].ravel(), m[:, :6].ravel(),
            m[:, -6:].ravel()])
    m_bg = float(np.median(frame))
    lo = min(KEY_LO, KEY_LO_K * m_bg)
    hi = min(KEY_HI, KEY_HI_K * m_bg)
    alpha = 1.0 - np.clip((m - lo) / (hi - lo), 0.0, 1.0)
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


def cut_add(img: Image.Image, grid: int, items: list) -> list:
    """Листы под сложение цвета (чёрный фон): ячейка по рамке, обрезка по
    светлому, края гаснут в ноль — иначе в игре виден светлый квадрат."""
    a = np.clip(np.asarray(img.convert("RGB")).astype(np.float32) - ADD_FLOOR,
            0.0, 255.0)
    h, w = a.shape[:2]
    out = []
    for i, (name, size) in enumerate(items):
        if not name:
            continue
        cy, cx = divmod(i, grid)
        cell = a[cy * h // grid:(cy + 1) * h // grid,
                cx * w // grid:(cx + 1) * w // grid]
        ys, xs = np.nonzero(cell.max(axis=2) > 10.0)
        if len(ys) == 0:
            raise SystemExit(f"пустая ячейка {name}")
        y0, y1 = max(ys.min() - 8, 0), min(ys.max() + 9, cell.shape[0])
        x0, x1 = max(xs.min() - 8, 0), min(xs.max() + 9, cell.shape[1])
        piece = cell[y0:y1, x0:x1]
        ph, pw = piece.shape[:2]
        fy = np.sin(np.linspace(0.0, np.pi, ph))[:, None] ** 0.5
        fx = np.sin(np.linspace(0.0, np.pi, pw))[None, :] ** 0.5
        piece = piece * (fy * fx)[..., None]
        rgba = np.dstack([piece, np.full((ph, pw), 255.0)])
        out.append((name, size, rgba.astype(np.uint8)))
    return out


def road_texture(img: Image.Image) -> Image.Image:
    """Полотно: асфальт, сгенерированный здесь же, цвет — средний у
    присланной картинки. Сами присланные (art/env_*/road.jpg) — сетка
    плоских прямоугольников разного серого с трещинами: на трассе
    читались заплатками (замечание игрока 23.10), сглаживание и сведение
    швов не помогали — прямоугольники оставались.
    Шум — белый, отфильтрованный в частотах (БПФ), поэтому тайл бесшовный
    по построению: мягкие пятна износа ~3 м, щебень, ветвящиеся трещины
    (road_cracks). Мелкого зерна нет: на экране тайл ужат в ~4 раза, зерно
    сливалось в ровный тон и только раздувало файл."""
    base = np.asarray(img.convert("RGB")).astype(np.float32).reshape(-1, 3).mean(0)
    n = ROAD_PX
    rng = np.random.default_rng(20261023)
    f = np.fft.fftfreq(n)
    fr = np.sqrt(f[:, None] ** 2 + f[None, :] ** 2) * n   # циклов на тайл

    def band(lo, hi):
        spec = np.fft.fft2(rng.standard_normal((n, n)))
        spec *= (fr >= lo) & (fr < hi)
        out = np.real(np.fft.ifft2(spec))
        return out / (out.std() + 1e-9)

    # Тайл ROAD_TILE_M: пятна 2–7 м и 0.5–2 м.
    k = ROAD_TILE_M
    lum = 1.0 + 0.045 * band(k / 7.0, k / 2.0) + 0.03 * band(k / 2.0, k / 0.5)
    # Щебень: редкие светлые и тёмные крупинки ~3 см.
    specks = rng.random((n, n))
    grit = np.where(specks > 0.9992, 0.25, 0.0) - np.where(specks < 0.0008, 0.15, 0.0)
    lum += ndimage.maximum_filter(grit, 3) + ndimage.minimum_filter(grit, 3)
    lum -= ROAD_CRACK_DEPTH * road_cracks(n, rng)
    a = base[None, None, :] * lum[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")


def road_cracks(n: int, rng) -> np.ndarray:
    """Маска трещин 0..1 на бесшовном тайле n×n: почти прямые отрезки с
    редкими резкими изломами и ветками, толщина сходит на нет к концу;
    отрезок у края рисуется ещё и со сдвигом на ±n — продолжение на
    соседнем тайле. Старты — по одному в случайных клетках сетки 3×3, чтобы
    трещины не сбивались в кучу. Было: извив на каждом шаге — выходили
    волоски и прожилки, а не трещины."""
    from PIL import ImageDraw
    canvas = Image.new("L", (n, n), 0)
    draw = ImageDraw.Draw(canvas)
    px_m = n / ROAD_TILE_M

    def seg(x0, y0, x1, y1, w):
        for dx in (-n, 0, n):
            for dy in (-n, 0, n):
                draw.line((x0 + dx, y0 + dy, x1 + dx, y1 + dy), fill=255,
                        width=max(1, int(round(w))))

    def walk(x, y, ang, length, w, depth):
        step = 0.05 * px_m   # 5 см
        steps = int(length / step)
        for i in range(steps):
            ang += rng.normal(0.0, 0.04)
            if rng.random() < 0.035:   # излом
                ang += rng.choice((-1, 1)) * rng.uniform(0.35, 0.9)
            nx, ny = x + np.cos(ang) * step, y + np.sin(ang) * step
            seg(x, y, nx, ny, max(2.0, w * (1.0 - 0.7 * i / steps)))
            x, y = nx % n, ny % n
            if depth < 2 and rng.random() < 0.02:
                walk(x, y, ang + rng.choice((-1, 1)) * rng.uniform(0.5, 1.3),
                        length * rng.uniform(0.3, 0.6), w * 0.65, depth + 1)

    cells = rng.permutation(9)[:ROAD_CRACKS]
    for c in cells:
        cy, cx = divmod(int(c), 3)
        walk((cx + rng.uniform(0.15, 0.85)) * n / 3.0,
                (cy + rng.uniform(0.15, 0.85)) * n / 3.0,
                rng.uniform(0, 2 * np.pi), rng.uniform(5.0, 11.0) * px_m,
                ROAD_CRACK_W * px_m, 0)
    m = np.asarray(canvas.filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32)
    return m / 255.0


ROAD_PX = 2048          # сторона тайла полотна, px
ROAD_TILE_M = 20.0      # ...в метрах (= TrackBuilder.ROAD_TILE)
ROAD_CRACKS = 6         # трещин на тайл (с ветками), не больше 9
ROAD_CRACK_W = 0.09     # толщина трещины у начала, м
ROAD_CRACK_DEPTH = 0.6  # насколько трещина темнее асфальта (0.45 — едва видно в игре)


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
    ground = Image.open(source(src, "ground")).convert("RGB")
    if "ground_contrast" in cfg:
        g = np.asarray(ground).astype(np.float32)
        mean = g.reshape(-1, 3).mean(0)
        g = mean + (g - mean) * cfg["ground_contrast"]
        ground = Image.fromarray(np.clip(g, 0, 255).astype(np.uint8), "RGB")
    ground.save(os.path.join(dst, "ground.png"))
    title = track.capitalize()
    lines = [
        "extends RefCounted",
        "## СГЕНЕРИРОВАНО tools/gen_env.py — руками не править.",
        f"## Куски атласов 2D-окружения трассы «{track}»:",
        "## имя -> [x, y, ширина, высота в px атласа, размер в метрах].",
        "## У картонок размер — высота на экране, у плоских кусков — ширина.",
        "",
        f'const GROUND := "{res}ground.png"',
    ]
    if cfg.get("road"):
        road_texture(Image.open(source(src, "road"))).save(
                os.path.join(dst, "road.png"))
        lines.append(f'const ROAD := "{res}road.png"')
    lines.append("")
    table = []
    for sheet, spec in cfg["sheets"].items():
        grid, flat, unshaded, items = spec[:4]
        additive = len(spec) > 4 and spec[4] == "add"
        img = Image.open(source(src, sheet))
        pieces = cut_add(img, grid, items) if additive else \
                cut(key_out(img, cfg["key"]), grid, items)
        atlas, rects = pack(pieces)
        Image.fromarray(atlas, "RGBA").save(os.path.join(dst, sheet + ".png"))
        lines.append(f"const {sheet.upper()} := {{")
        for name, x, y, w, h, size in rects:
            lines.append(f'\t"{name}": [{x}, {y}, {w}, {h}, {float(size)}],')
        lines.append("}")
        lines.append("")
        table.append(f'\t"{sheet}": ["{res}{sheet}.png", {sheet.upper()}, '
                f"{str(flat).lower()}, {str(unshaded).lower()}, "
                f"{str(additive).lower()}],")
        print(track, sheet, len(rects), "pieces, atlas",
                atlas.shape[1], "x", atlas.shape[0])
    lines.append("## Лист -> [атлас, куски, плоский (лежит на земле), без освещения,")
    lines.append("## сложением цвета (чёрное = прозрачно)].")
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
