# -*- coding: utf-8 -*-
"""Генерация UI-ассетов «гаражного» стиля из референсов в корне проекта.

Запуск:  py tools/gen_ui_assets.py   (из корня проекта)

Делает:
  1. Режет 8 восьмиугольных оружейных значков из
     _STYLE_CORE_A_sheet_of_12_weap_2.jpg (сетка 5x3, фон убирается
     заливкой от краёв ячейки) -> assets/ui/garage/wg_*.png
  2. Режет пустой гекс-слот (состояние EMPTY) из
     _STYLE_CORE_A_HUD_weapon_slot__2.jpg -> slot_empty.png
  3. Запекает эмалевые таблички с заклёпками (белая/жёлтая/оранжевая/
     красная/бирюзовая/стальная) -> plate_*.png (9-slice, поля 40 px)
  4. Запекает тайлы: аварийные полосы hazard.png, шахматка checker.png
  5. Собирает контрольный лист preview.png (для глаз)
"""
import os
import glob
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui", "garage")
os.makedirs(OUT, exist_ok=True)

INK = (23, 27, 32)
STEEL = (38, 43, 49)
RIM = (90, 98, 107)
WHITE = (239, 232, 216)
YELLOW = (242, 194, 28)
ORANGE = (232, 100, 27)
RED = (207, 51, 39)
TEAL = (43, 191, 174)


def flood_from_border(arr_rgb, tol=60.0):
    """Маска фона: пиксели, похожие на цвет краёв и ДОСТИЖИМЫЕ с краёв.

    Замкнутые тёмные области внутри значка (интерьер мины и т.п.)
    заливка не съест — до них с краёв не добраться.
    """
    h, w, _ = arr_rgb.shape
    border = np.concatenate([arr_rgb[0], arr_rgb[-1], arr_rgb[:, 0],
                             arr_rgb[:, -1]]).astype(np.float32)
    bg = np.median(border, axis=0)
    dist = np.sqrt(((arr_rgb.astype(np.float32) - bg) ** 2).sum(axis=2))
    candidate = dist < tol
    reached = np.zeros((h, w), dtype=bool)
    reached[0, :] = candidate[0, :]
    reached[-1, :] = candidate[-1, :]
    reached[:, 0] = candidate[:, 0]
    reached[:, -1] = candidate[:, -1]
    while True:
        grown = reached.copy()
        grown[1:, :] |= reached[:-1, :]
        grown[:-1, :] |= reached[1:, :]
        grown[:, 1:] |= reached[:, :-1]
        grown[:, :-1] |= reached[:, 1:]
        grown &= candidate
        if (grown == reached).all():
            return grown
        reached = grown


def cut_badge(sheet, col, row, cols=5, rows=3, y0f=0.0, y1f=1.0,
              out_size=256, tol=60.0):
    """Вырезать значок из ячейки листа, фон -> прозрачность."""
    w, h = sheet.size
    cw, ch = w / cols, h / rows
    box = (int(col * cw), int(row * ch + y0f * ch),
           int((col + 1) * cw), int(row * ch + y1f * ch))
    cell = sheet.crop(box).convert("RGB")
    arr = np.asarray(cell)
    bg = flood_from_border(arr, tol)
    alpha = np.where(bg, 0, 255).astype(np.uint8)
    a_img = Image.fromarray(alpha, "L").filter(ImageFilter.GaussianBlur(1.0))
    rgba = cell.convert("RGBA")
    rgba.putalpha(a_img)
    bbox = a_img.point(lambda p: 255 if p > 24 else 0).getbbox()
    if bbox is None:
        raise RuntimeError("пустая ячейка %d,%d" % (col, row))
    rgba = rgba.crop(bbox)
    side = max(rgba.size) + 16
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(rgba, ((side - rgba.width) // 2, (side - rgba.height) // 2))
    return sq.resize((out_size, out_size), Image.LANCZOS)


def bake_plate(color, rim_color=None, w=384, h=192, r=18, stroke=3,
               rivet_inset=24, rivet_r=8):
    """Эмалевая табличка: скруглённая пластина, глянец, кант, заклёпки."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=r, fill=color + (255,))
    arr = np.asarray(img).astype(np.float32)
    # Вертикальный глянец: светлее сверху, темнее к низу.
    grad = np.linspace(1.10, 0.90, h)[:, None, None]
    arr[:, :, :3] *= grad
    # Мягкая бликовая полоса у верхней кромки.
    band = np.zeros((h, 1, 1), dtype=np.float32)
    y = np.arange(h)
    band[:, 0, 0] = np.clip(1.0 - np.abs(y - h * 0.16) / (h * 0.14), 0, 1) * 14
    arr[:, :, :3] += band
    # Лёгкий шум, чтобы эмаль не была пластиково-плоской.
    rng = np.random.default_rng(7)
    arr[:, :, :3] += rng.normal(0, 2.5, (h, w, 1))
    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(out)
    # Кант: тёмная сталь снаружи, тонкий светлый блик внутри.
    edge = rim_color if rim_color else (30, 34, 39)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=r, outline=edge + (255,),
                        width=stroke)
    d.rounded_rectangle((stroke, stroke, w - 1 - stroke, h - 1 - stroke),
                        radius=max(2, r - stroke),
                        outline=(255, 255, 255, 55), width=1)
    # Заклёпки по углам.
    hi = max(1, rivet_r // 3)
    for cx, cy in ((rivet_inset, rivet_inset), (w - rivet_inset, rivet_inset),
                   (rivet_inset, h - rivet_inset),
                   (w - rivet_inset, h - rivet_inset)):
        d.ellipse((cx - rivet_r, cy - rivet_r, cx + rivet_r, cy + rivet_r),
                  fill=(86, 93, 101, 255), outline=(25, 29, 34, 255), width=2)
        d.ellipse((cx - rivet_r + hi, cy - rivet_r + hi, cx - hi, cy - hi),
                  fill=(230, 235, 240, 190))
    # Маска прозрачности заново (шум мог тронуть углы).
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=r,
                                           fill=255)
    out.putalpha(mask)
    return out


def bake_arrow(direction=-1):
    """Квадратная оранжевая табличка с чернильным треугольником-стрелкой."""
    img = bake_plate(ORANGE, w=96, h=96, r=12, stroke=2, rivet_inset=13,
                     rivet_r=5)
    d = ImageDraw.Draw(img)
    cx, cy, s = 48, 48, 20
    if direction < 0:
        pts = [(cx + s * 0.7, cy - s), (cx + s * 0.7, cy + s),
               (cx - s * 0.9, cy)]
    else:
        pts = [(cx - s * 0.7, cy - s), (cx - s * 0.7, cy + s),
               (cx + s * 0.9, cy)]
    d.polygon(pts, fill=INK + (255,))
    return img


def bake_hazard(w=128, h=32, period=32):
    """Аварийные жёлто-чёрные полосы под 45°, тайлится по горизонтали."""
    xx, yy = np.meshgrid(np.arange(w), np.arange(h))
    stripe = ((xx + yy) % period) < period // 2
    arr = np.where(stripe[:, :, None], np.array(YELLOW), np.array(INK))
    rng = np.random.default_rng(3)
    arr = arr.astype(np.float32) + rng.normal(0, 4, (h, w, 1))
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")


def bake_checker(sq=12, cols=8, rows=2):
    """Шахматная лента (финиш)."""
    w, h = sq * cols, sq * rows
    xx, yy = np.meshgrid(np.arange(w), np.arange(h))
    cell = ((xx // sq + yy // sq) % 2) == 0
    arr = np.where(cell[:, :, None], np.array(WHITE), np.array(INK))
    return Image.fromarray(arr.astype(np.uint8), "RGB")


def main():
    def sheet(pattern):
        path = glob.glob(os.path.join(ROOT, pattern))[0]
        return Image.open(path)

    weap = sheet("_STYLE_CORE_A_sheet_of_12_weap_2.jpg")
    # (колонка, ряд) в сетке 5x3 листа значков.
    mapping = {
        "wg_oil": (0, 0), "wg_rocket": (2, 0), "wg_freeze": (3, 0),
        "wg_airstrike": (0, 1), "wg_magnet": (1, 1), "wg_laser": (3, 1),
        "wg_mine": (0, 2), "wg_boost": (4, 2),
    }
    made = {}
    for name, (c, r) in mapping.items():
        img = cut_badge(weap, c, r)
        img.save(os.path.join(OUT, name + ".png"))
        made[name] = img

    hud = sheet("_STYLE_CORE_A_HUD_weapon_slot__2.jpg")
    # y1f режет ДО подписи "EMPTY" под гексом — иначе она попадает в кадр.
    slot = cut_badge(hud, 0, 0, cols=5, rows=1, y0f=0.28, y1f=0.665, tol=42.0)
    slot.save(os.path.join(OUT, "slot_empty.png"))
    made["slot_empty"] = slot

    plates = {
        "plate_white": (WHITE, None), "plate_yellow": (YELLOW, None),
        "plate_orange": (ORANGE, None), "plate_red": (RED, None),
        "plate_teal": (TEAL, None), "plate_steel": (STEEL, RIM),
    }
    for name, (color, rim) in plates.items():
        img = bake_plate(color, rim)
        img.save(os.path.join(OUT, name + ".png"))
        made[name] = img
        # Малый вариант — для панелей HUD (9-slice поля 20 px).
        small = bake_plate(color, rim, w=256, h=96, r=10, stroke=2,
                           rivet_inset=13, rivet_r=5)
        small.save(os.path.join(OUT, name + "_s.png"))

    bake_arrow(-1).save(os.path.join(OUT, "arrow_l.png"))
    bake_arrow(1).save(os.path.join(OUT, "arrow_r.png"))
    made["arrow_l"] = bake_arrow(-1)

    bake_hazard().save(os.path.join(OUT, "hazard.png"))
    bake_checker().save(os.path.join(OUT, "checker.png"))

    # Фон лобби: ржавая панель из референса, затемнённая до «сумрака
    # гаража» (текстура и так бесшовная).
    rust = sheet("A_seamless_tileable_texture_he_2.jpg").convert("RGB")
    rust = rust.resize((1024, 571), Image.LANCZOS)
    arr = np.asarray(rust).astype(np.float32) * 0.30
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").save(
        os.path.join(OUT, "backdrop_rust.jpg"), quality=88)

    # Контрольный лист.
    prev = Image.new("RGB", (5 * 200, 4 * 200), (52, 56, 60))
    for i, (name, img) in enumerate(sorted(made.items())):
        x, y = (i % 5) * 200, (i // 5) * 200
        t = img.copy()
        t.thumbnail((180, 180))
        prev.paste(t, (x + (200 - t.width) // 2, y + (200 - t.height) // 2),
                   t if t.mode == "RGBA" else None)
    prev.paste(bake_hazard(), (20, 3 * 200 + 60))
    prev.paste(bake_checker(), (220, 3 * 200 + 60))
    prev.save(os.path.join(OUT, "_preview.png"))
    print("ok ->", OUT)


if __name__ == "__main__":
    main()
