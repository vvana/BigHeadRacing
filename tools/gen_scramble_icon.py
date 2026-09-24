# -*- coding: utf-8 -*-
"""Значок оружия «Глушилка» (перекрещённые стрелки) в стиле остальных.

Запуск:  py tools/gen_scramble_icon.py   (из корня проекта)

В листе-референсе (_STYLE_CORE_A_sheet_of_12_weap_2.jpg, режется
tools/gen_ui_assets.py) звуковой волны нет, поэтому восьмиугольник
запекается с нуля по тем же правилам: стальной кант с заклёпками, цветная
эмаль, аварийная полоса внизу, чернильный символ: две перекрещённые
стрелки в разные стороны — «лево и право перепутаны» (до 23.09 была
звуковая волна). Цвет — бирюзовый, как у самой волны в игре (ScrambleWave).

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


def arrow(d, a, b, n, fill, halo=0.0):
    """Толстая стрелка из a в b: прямоугольное древко и треугольный
    наконечник; halo расширяет контур (просвет вокруг верхней стрелки)."""
    ax, ay = a
    bx, by = b
    L = math.hypot(bx - ax, by - ay)
    ux, uy = (bx - ax) / L, (by - ay) / L      # вдоль
    px, py = -uy, ux                           # поперёк
    shaft = n * 0.030 + halo
    head_w = n * 0.085 + halo
    head_l = n * 0.14 + halo * 0.8
    tail_x, tail_y = ax - ux * halo, ay - uy * halo
    tip_x, tip_y = bx + ux * halo * 0.9, by + uy * halo * 0.9
    base_x, base_y = tip_x - ux * head_l, tip_y - uy * head_l
    d.polygon([(tail_x + px * shaft, tail_y + py * shaft),
               (base_x + px * shaft, base_y + py * shaft),
               (base_x - px * shaft, base_y - py * shaft),
               (tail_x - px * shaft, tail_y - py * shaft)], fill=fill)
    d.polygon([(base_x + px * head_w, base_y + py * head_w),
               (tip_x, tip_y),
               (base_x - px * head_w, base_y - py * head_w)], fill=fill)


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

    # Символ: две перекрещённые стрелки в разные стороны — «лево и право
    # перепутаны» (просьба 23.09; прежде была звуковая волна). Задняя
    # стрелка идёт из правого низа в левый верх, передняя — из левого
    # низа в правый верх и лежит ПОВЕРХ (эмалевый просвет по контуру):
    # читается как перекрёсток, а не как крестик.
    # Символ приподнят (cy): внизу восьмиугольника идёт аварийная полоса,
    # и посаженный по центру знак сливался бы с ней в одно тёмное пятно.
    cy = c - n * 0.045
    back = ((c + n * 0.23, cy + n * 0.16), (c - n * 0.26, cy - n * 0.16))
    front = ((c - n * 0.23, cy + n * 0.16), (c + n * 0.26, cy - n * 0.16))
    arrow(d, back[0], back[1], n, INK + (255,))
    arrow(d, front[0], front[1], n, TEAL + (255,), halo=n * 0.024)
    arrow(d, front[0], front[1], n, INK + (255,))

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
