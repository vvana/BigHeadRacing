# -*- coding: utf-8 -*-
"""Текстура футбольного мяча (усечённый икосаэдр: 12 чёрных пятиугольников,
20 белых шестиугольников, тёмные швы) в равнопромежуточной развёртке —
под UV-сферу Godot (SphereMesh: u — долгота, v — широта от полюса).
Запуск: py tools/make_soccer_ball.py  → assets/fx/soccer_ball.png
"""
import math, os
import numpy as np
from PIL import Image

W, H = 1024, 512
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "fx", "soccer_ball.png")

phi = (1.0 + math.sqrt(5.0)) / 2.0
# 12 вершин икосаэдра — центры пятиугольников.
verts = []
for a in (-1, 1):
    for b in (-phi, phi):
        verts += [(0, a, b), (a, b, 0), (b, 0, a)]
verts = np.array(verts, dtype=np.float64)
verts /= np.linalg.norm(verts, axis=1)[:, None]
# Слегка повернём, чтобы полюса текстуры не попали ровно в пятиугольник.
def rot(v, ax, ang):
    c, s = math.cos(ang), math.sin(ang)
    x, y, z = v[:, 0].copy(), v[:, 1].copy(), v[:, 2].copy()
    if ax == "x":
        v[:, 1], v[:, 2] = c * y - s * z, s * y + c * z
    elif ax == "z":
        v[:, 0], v[:, 1] = c * x - s * y, s * x + c * y
    return v
verts = rot(rot(verts, "x", 0.35), "z", 0.2)

# 20 граней — центры шестиугольников: тройки вершин на расстоянии ребра.
edge = 2.0 / math.sqrt(phi * math.sqrt(5.0))  # ~1.0515 для единичной сферы
faces = []
n = len(verts)
for i in range(n):
    for j in range(i + 1, n):
        for k in range(j + 1, n):
            d1 = np.linalg.norm(verts[i] - verts[j])
            d2 = np.linalg.norm(verts[j] - verts[k])
            d3 = np.linalg.norm(verts[i] - verts[k])
            if abs(d1 - edge) < 0.05 and abs(d2 - edge) < 0.05 and abs(d3 - edge) < 0.05:
                c = verts[i] + verts[j] + verts[k]
                faces.append(c / np.linalg.norm(c))
faces = np.array(faces)
assert len(faces) == 20, len(faces)

# Направление каждого текселя.
u = (np.arange(W) + 0.5) / W
v = (np.arange(H) + 0.5) / H
lon = u * 2 * math.pi
lat = v * math.pi          # 0 — верхний полюс
LON, LAT = np.meshgrid(lon, lat)
dx = np.sin(LAT) * np.cos(LON)
dz = np.sin(LAT) * np.sin(LON)
dy = np.cos(LAT)
D = np.stack([dx, dy, dz], axis=-1)  # H×W×3

# Угловые расстояния до 32 центров. Пятиугольники «весят» больше —
# они меньше шестиугольников (на реальном мяче отношение ~0.7).
PENT_W = 1.27
dp = np.arccos(np.clip(D @ verts.T, -1, 1)) * PENT_W   # H×W×12
dh = np.arccos(np.clip(D @ faces.T, -1, 1))            # H×W×20
allc = np.concatenate([dp, dh], axis=-1)
order = np.argsort(allc, axis=-1)
nearest = order[..., 0]
d1 = np.take_along_axis(allc, order[..., :1], axis=-1)[..., 0]
d2 = np.take_along_axis(allc, order[..., 1:2], axis=-1)[..., 0]
is_pent = nearest < 12
seam = (d2 - d1) < 0.045

img = np.empty((H, W, 3), dtype=np.float64)
white = np.array([0.95, 0.95, 0.93])
black = np.array([0.07, 0.07, 0.09])
seam_c = np.array([0.55, 0.55, 0.53])
img[:] = white
img[is_pent] = black
# Швы — только между белыми панелями (у чёрных край и так контрастный),
# плюс лёгкая тёмная кромка у чёрных.
img[seam & ~is_pent] = seam_c
# Лёгкая виньетка-«потёртость», чтобы белое не было плоским.
noise = np.random.RandomState(7).uniform(-0.03, 0.03, size=(H, W, 1))
img = np.clip(img + noise, 0, 1)
Image.fromarray((img * 255).astype(np.uint8)).save(OUT)
print("saved", OUT)
