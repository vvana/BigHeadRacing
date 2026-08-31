# -*- coding: utf-8 -*-
"""Значок оружия «Глушилка» (звуковая волна) в стиле остальных.

Запуск:  py tools/gen_scramble_icon.py   (из корня проекта)

В листе-референсе (_STYLE_CORE_A_sheet_of_12_weap_2.jpg, режется
tools/gen_ui_assets.py) звуковой волны нет, поэтому восьмиугольник
запекается с нуля по тем же правилам: стальной кант с заклёпками, цветная
эмаль, аварийная полоса внизу, чернильный символ. Цвет — бирюзовый, как у
самой волны в игре (ScrambleWave).

Результат: assets/ui/garage/wg_scramble.png (256x256, RGBA).
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui", "garage", "wg_scramble.png")

SIZE = 256
SS = 4  # суперсэмплинг: рисуем вчетверо крупнее, потом уменьшаем

INK = (20, 24, 29)
TEAL = (46, 176, 196)
TEAL_DARK = (24, 104, 122)
STEEL = (120, 129, 138)
STEEL_DARK = (58, 65, 73)
YELLOW = (242, 194, 28)


def octagon(cx, cy, r, rot=math.pi / 8):
    return [(cx + r * math.cos(rot + i * math.pi / 4),
             cy + r * math.sin(rot + i * math.pi / 4)) for i in range(8)]


def main():
    n = SIZE * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = n / 2

    # Стальной кант и эмалевое поле.
    d.polygon(octagon(c, c, n * 0.48), fill=STEEL + (255,),
              outline=STEEL_DARK + (255,), width=int(n * 0.012))
    d.polygon(octagon(c, c, n * 0.425), fill=TEAL_DARK + (255,))
    d.polygon(octagon(c, c, n * 0.40), fill=TEAL + (255,))

    # Заклёпки по граням канта.
    rr = n * 0.022
    for i in range(8):
        a = math.pi / 8 + i * math.pi / 4 + math.pi / 8
        px, py = c + n * 0.445 * math.cos(a), c + n * 0.445 * math.sin(a)
        d.ellipse((px - rr, py - rr, px + rr, py + rr),
                  fill=(96, 104, 112, 255), outline=INK + (255,),
                  width=int(n * 0.004))
        d.ellipse((px - rr * 0.45, py - rr * 0.45, px + rr * 0.1,
                   py + rr * 0.1), fill=(228, 234, 240, 200))

    # Символ: излучатель слева и три расходящиеся дуги вправо —
    # «оглушающая волна».
    # Символ приподнят (cy): внизу восьмиугольника идёт аварийная полоса,
    # и посаженный по центру знак сливался бы с ней в одно тёмное пятно.
    cy = c - n * 0.045
    horn = [(c - n * 0.24, cy - n * 0.13), (c - n * 0.09, cy - n * 0.13),
            (c - n * 0.09, cy + n * 0.13), (c - n * 0.24, cy + n * 0.13)]
    d.polygon(horn, fill=INK + (255,))
    d.polygon([(c - n * 0.09, cy - n * 0.17), (c + n * 0.01, cy - n * 0.25),
               (c + n * 0.01, cy + n * 0.25), (c - n * 0.09, cy + n * 0.17)],
              fill=INK + (255,))
    for k, rad in enumerate((0.09, 0.165, 0.24)):
        w = int(n * (0.030 - 0.005 * k))
        box = (c + n * 0.01 - n * rad, cy - n * rad,
               c + n * 0.01 + n * rad, cy + n * rad)
        d.arc(box, start=-58, end=58, fill=INK + (255,), width=w)

    # Аварийная полоса внизу — как на значках из листа.
    band_h = n * 0.075
    band = Image.new("RGBA", (n, int(band_h)), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    step = n * 0.055
    x = -band_h
    while x < n + band_h:
        bd.polygon([(x, band_h), (x + step / 2, band_h),
                    (x + step / 2 + band_h, 0), (x + band_h, 0)],
                   fill=YELLOW + (255,))
        x += step
    strip = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    strip.paste(Image.new("RGBA", (n, int(band_h)), INK + (255,)),
                (0, int(c + n * 0.24)))
    strip.alpha_composite(band, (0, int(c + n * 0.24)))
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).polygon(octagon(c, c, n * 0.40), fill=255)
    img.paste(strip, (0, 0), Image.fromarray(
        np.minimum(np.asarray(mask), np.asarray(strip.split()[3])), "L"))

    # Глянец сверху вниз и лёгкий шум — эмаль, а не пластик.
    arr = np.asarray(img).astype(np.float32)
    grad = np.linspace(1.12, 0.88, n)[:, None, None]
    arr[:, :, :3] *= grad
    rng = np.random.default_rng(11)
    arr[:, :, :3] += rng.normal(0, 2.0, (n, n, 1))
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")

    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img.putalpha(img.split()[3].filter(ImageFilter.GaussianBlur(0.4)))
    img.save(OUT)
    print("ok ->", OUT)


if __name__ == "__main__":
    main()
