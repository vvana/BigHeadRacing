# -*- coding: utf-8 -*-
"""Ассеты гаража-меню (03.09.2026): монета-гайка, значок «ролик» и
текстуры бокса. Отдельно от gen_ui_assets.py — тот перезаписывает
значки оружия, а wg_mine.png правился руками (.bak рядом).

Запуск:  py tools/gen_garage_assets.py   (из корня проекта)

  assets/ui/garage/coin.png          — жёлтая гайка-монета (64x64)
  assets/ui/garage/play.png          — белый треугольник «ролик» (40x40)
  assets/ui/garage/wall_panels.png   — светлая рифлёная стена, тайл
  assets/ui/garage/concrete.png      — тёплый бетон пола, тайл
  assets/ui/garage/diamond_orange.jpg — оранжевый рифлёный лист
                                        (референс из корня, 1024 px)
"""
import os
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui", "garage")
os.makedirs(OUT, exist_ok=True)

INK = (23, 27, 32)
YELLOW = (242, 194, 28)
YELLOW_DARK = (196, 150, 14)


def hexagon(cx, cy, r, rot=0.0):
    return [(cx + r * math.cos(rot + i * math.pi / 3),
             cy + r * math.sin(rot + i * math.pi / 3)) for i in range(6)]


def bake_coin(size=64):
    """Гайка-монета: жёлтый шестигранник с чернильным кантом и отверстием."""
    s = size * 4  # рисуем крупно, потом уменьшаем — гладкие кромки
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = s / 2
    d.polygon(hexagon(c, c, s * 0.47), fill=INK + (255,))
    d.polygon(hexagon(c, c, s * 0.41), fill=YELLOW + (255,))
    # Тень нижних граней — объём.
    d.polygon(hexagon(c, c + s * 0.03, s * 0.41), fill=YELLOW_DARK + (110,))
    d.polygon(hexagon(c, c, s * 0.41), fill=YELLOW + (0,))
    d.polygon(hexagon(c, c - s * 0.015, s * 0.385), fill=YELLOW + (255,))
    # Отверстие.
    d.ellipse((c - s * 0.17, c - s * 0.17, c + s * 0.17, c + s * 0.17),
              fill=INK + (255,))
    d.ellipse((c - s * 0.12, c - s * 0.12, c + s * 0.12, c + s * 0.12),
              fill=YELLOW_DARK + (255,))
    # Блик.
    d.pieslice((c - s * 0.36, c - s * 0.36, c + s * 0.36, c + s * 0.36),
               200, 250, fill=(255, 255, 255, 70))
    return img.resize((size, size), Image.LANCZOS)


def bake_play(size=40):
    """Треугольник «ролик»: белый с чернильной обводкой (на бирюзе)."""
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pts = [(s * 0.22, s * 0.12), (s * 0.22, s * 0.88), (s * 0.88, s * 0.5)]
    d.polygon(pts, fill=INK + (255,))
    inner = [(s * 0.30, s * 0.26), (s * 0.30, s * 0.74), (s * 0.76, s * 0.5)]
    d.polygon(inner, fill=(255, 255, 255, 255))
    return img.resize((size, size), Image.LANCZOS)


def noise(h, w, seed, octaves=(4, 16, 64), amp=1.0):
    rng = np.random.default_rng(seed)
    acc = np.zeros((h, w), dtype=np.float32)
    for k, cells in enumerate(octaves):
        small = rng.normal(0, 1, (cells, cells)).astype(np.float32)
        img = Image.fromarray(small, "F").resize((w, h), Image.BICUBIC)
        acc += np.asarray(img) * (amp / (k + 1))
    return acc


def bake_wall(w=256, h=512, ribs=8):
    """Светлая рифлёная стена бокса: горизонтальные панели, шов снизу."""
    base = np.array((201, 193, 180), dtype=np.float32)
    yy = np.arange(h)[:, None]
    period = h / ribs
    t = (yy % period) / period                      # 0..1 внутри панели
    shade = 1.0 + 0.10 * np.cos(t * 2 * math.pi)    # выпуклая панель
    seam = np.where(t > 0.94, 0.68, 1.0)            # тёмный шов
    arr = np.ones((h, w, 3), dtype=np.float32) * base
    arr *= (shade * seam)[:, :, None]
    arr += noise(h, w, 11, (8, 32, 128), 3.0)[:, :, None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")


def bake_concrete(size=512):
    """Тёплый серый бетон с пятнами — пол бокса."""
    base = np.array((150, 145, 138), dtype=np.float32)
    n = noise(size, size, 5, (4, 8, 32, 128), 9.0)
    arr = np.ones((size, size, 3), dtype=np.float32) * base + n[:, :, None]
    # Мелкая крошка.
    rng = np.random.default_rng(9)
    arr += rng.normal(0, 3.5, (size, size, 1))
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")


def main():
    bake_coin().save(os.path.join(OUT, "coin.png"))
    bake_play().save(os.path.join(OUT, "play.png"))
    bake_wall().save(os.path.join(OUT, "wall_panels.png"))
    bake_concrete().save(os.path.join(OUT, "concrete.png"))
    src = os.path.join(ROOT, "A_seamless_tileable_texture_he_1.jpg")
    dia = Image.open(src).convert("RGB")
    dia = dia.resize((1024, int(1024 * dia.height / dia.width)), Image.LANCZOS)
    dia.save(os.path.join(OUT, "diamond_orange.jpg"), quality=88)
    print("ok ->", OUT)


if __name__ == "__main__":
    main()
