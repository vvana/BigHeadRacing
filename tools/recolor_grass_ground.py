"""Зелёная земля «Травы» (23.10.2026): перекраска прежней выгоревшей земли
ИИ-художника (art/env_grass/unused/ground_dry.webp) в сочную траву —
охра, солома и олива (тон 20–75°) уходят в зелень 98–126°, земля чуть
темнее. Присланная новая «бесшовная» трава (unused/ground_quilt.jpg) — лоскутное
одеяло из трёх плоских квадратов со швом по вертикали, не взята.

Запуск: py -3 tools/recolor_grass_ground.py  -> art/env_grass/ground.png
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
src = Image.open(os.path.join(ROOT, "art/env_grass/unused/ground_dry.webp")).convert("HSV")
hsv = np.asarray(src).astype(np.float32) / 255.0
h, s, v = hsv[..., 0] * 360.0, hsv[..., 1], hsv[..., 2]
t = np.clip((h - 20.0) / 55.0, 0.0, 1.0)
h2 = 98.0 + t * 28.0
s2 = np.clip(s * 0.72 + 0.05, 0.0, 1.0)
v2 = np.clip(v * 0.74, 0.0, 1.0)
out = np.dstack([h2 / 360.0, s2, v2]) * 255.0
Image.fromarray(out.astype(np.uint8), "HSV").convert("RGB").save(
        os.path.join(ROOT, "art/env_grass/ground.png"))
