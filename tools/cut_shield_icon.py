# -*- coding: utf-8 -*-
"""Значок бонуса «Щит» — вырезка из картинки игрока (08.09).

Запуск:  py tools/cut_shield_icon.py <картинка>   (из корня проекта)

Игрок прислал стальной восьмиугольник с клёпаным щитом на тёмном фоне
(снимок экрана, по краям — обрезки соседних значков). Скрипт находит
восьмиугольник по светлым пикселям, вырезает квадрат вокруг него,
снимает фон маской-восьмиугольником и приводит к 256x256 RGBA — как у
значков из листа (tools/gen_ui_assets.py).

Результат: assets/ui/garage/wg_shield.png.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui", "garage", "wg_shield.png")
SIZE = 256


def octagon(cx, cy, r, rot=math.pi / 8):
    return [(cx + r * math.cos(rot + i * math.pi / 4),
             cy + r * math.sin(rot + i * math.pi / 4)) for i in range(8)]


def main(path):
    src = Image.open(path).convert("RGB")
    a = np.asarray(src).astype(np.int32)
    # Сталь значка — светлая и почти серая; фон тёмный, обрезки соседей
    # оранжевые (красный канал сильно выше синего).
    lum = a.sum(axis=2) / 3.0
    # Значок — связная область НЕтёмных пикселей вокруг центра картинки;
    # обрезки соседних значков по краям отделены тёмным фоном и в
    # заливку не попадают. Рамка области — сам восьмиугольник (плоские
    # грани сверху/снизу/по бокам): центр — середина рамки, апофема —
    # половина её ширины.
    light = lum > 45
    # Старт заливки — ближайший к центру светлый пиксель (в самом центре
    # может стоять чернильный контур эмблемы). Заливка — своя (BFS):
    # ImageDraw.floodfill на картинке из numpy молча ничего не красит.
    ly, lx = np.where(light)
    k = int(np.argmin((lx - src.size[0] / 2.0) ** 2 + (ly - src.size[1] / 2.0) ** 2))
    hh, ww = light.shape

    def flood(sy, sx):
        out = np.zeros_like(light)
        stack = [(sy, sx)]
        out[sy, sx] = True
        while stack:
            y, x = stack.pop()
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < hh and 0 <= nx < ww and light[ny, nx]                         and not out[ny, nx]:
                    out[ny, nx] = True
                    stack.append((ny, nx))
        return out

    # Первая заливка даёт ЭМБЛЕМУ (её отделяет от поля чернильный контур);
    # вторая — от точки правее эмблемы — само стальное поле восьмиугольника.
    emb = flood(int(ly[k]), int(lx[k]))
    ey, ex = np.where(emb)
    sy, sx = int((ey.min() + ey.max()) / 2), min(int(ex.max()) + 10, ww - 1)
    while sx < ww - 1 and not light[sy, sx]:
        sx += 1
    comp = flood(sy, sx)
    ys, xs = np.where(comp)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    apo = max(x1 - x0, y1 - y0) / 2.0
    r_out = apo / math.cos(math.pi / 8)
    print("bbox x %d..%d y %d..%d, center (%.1f, %.1f), r_out %.1f"
          % (x0, x1, y0, y1, cx, cy, r_out))
    # Залилось эмалевое ПОЛЕ (стальной кант отделён тёмной канавкой). У
    # значков листа поле — 0.40 стороны, кант — 0.48: квадрат считаем от
    # поля, маска ложится по канту.
    hi = int(round(r_out / 0.40 / 2.0))
    box = (int(round(cx)) - hi, int(round(cy)) - hi,
           int(round(cx)) + hi, int(round(cy)) + hi)
    crop = src.crop(box).convert("RGBA")
    n = crop.size[0]
    c = n / 2.0
    m = Image.new("L", (n, n), 0)
    ImageDraw.Draw(m).polygon(octagon(c, c, n * 0.482), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(0.6))
    crop.putalpha(m)
    crop = crop.resize((SIZE, SIZE), Image.LANCZOS)
    crop.save(OUT)
    print("ok ->", OUT)


if __name__ == "__main__":
    main(sys.argv[1])
