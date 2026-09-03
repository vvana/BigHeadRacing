# -*- coding: utf-8 -*-
"""Текстура подиума гаража (03.09.2026): тёмный стальной рифлёный лист
(«ёлочка» из выпуклых диамантов), бесшовный тайл 512 px. Отдельно от
gen_garage_assets.py — тот шумит без сида и перезаписал бы соседей.

Запуск:  py tools/gen_podium_tex.py   (из корня проекта)
  assets/ui/garage/podium_plate.png
"""
import os
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui", "garage", "podium_plate.png")


def diamond_plate(size=512, cell=64):
    """Сталь: базовый серый с лёгким шумом, поверх — ромбики-диаманты в
    шахматном порядке под 45°, светлая кромка сверху-слева, тень
    снизу-справа. Рисуем в высоте (heightmap) и «освещаем» градиентом,
    чтобы кромки были одинаковы и бесшовны."""
    rng = np.random.default_rng(7)
    h = np.zeros((size, size), dtype=np.float32)
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    # Диамант — вытянутый ромб; в соседних клетках повёрнут на 90°.
    for gy in range(-1, size // cell + 1):
        for gx in range(-1, size // cell + 1):
            cx = gx * cell + cell / 2
            cy = gy * cell + cell / 2
            horiz = (gx + gy) % 2 == 0
            L, W = cell * 0.36, cell * 0.11
            a = math.pi / 4 if horiz else -math.pi / 4
            pts = []
            for ox, oy in [(-L, 0), (0, -W), (L, 0), (0, W)]:
                pts.append((cx + ox * math.cos(a) - oy * math.sin(a),
                            cy + ox * math.sin(a) + oy * math.cos(a)))
            d.polygon(pts, fill=255)
    hm = np.asarray(img).astype(np.float32) / 255.0
    # Скруглить кромки — размытие с обёрткой (тайл).
    big = np.tile(hm, (3, 3))
    big = np.asarray(Image.fromarray((big * 255).astype(np.uint8))
                     .filter(ImageFilter.GaussianBlur(1.6))).astype(np.float32) / 255
    hm = big[size:2 * size, size:2 * size]
    # Освещение: градиент высоты вдоль (−1, −1) — свет сверху-слева.
    gx = np.roll(hm, -1, axis=1) - np.roll(hm, 1, axis=1)
    gy = np.roll(hm, -1, axis=0) - np.roll(hm, 1, axis=0)
    light = (-gx - gy) * 2.2
    base = 0.30 + hm * 0.10 + light
    # Мелкое зерно металла + крупные пятна потёртости.
    noise = rng.normal(0, 0.018, (size, size)).astype(np.float32)
    coarse = rng.normal(0, 1.0, (size // 16, size // 16)).astype(np.float32)
    coarse = np.asarray(Image.fromarray(np.clip(coarse * 40 + 128, 0, 255)
                                        .astype(np.uint8)).resize((size, size),
                                                                  Image.BILINEAR)
                        ).astype(np.float32) / 255 - 0.5
    v = np.clip(base + noise + coarse * 0.05, 0, 1)
    rgb = np.stack([v * 0.98, v * 1.0, v * 1.04], axis=-1)   # чуть холодная
    return Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB")


if __name__ == "__main__":
    diamond_plate().save(OUT)
    print("ok", OUT)
