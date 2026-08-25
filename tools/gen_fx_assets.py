# -*- coding: utf-8 -*-
"""Подготовка текстур спецэффектов из Epic Toon FX (Unity-ассет) в assets/fx/.

Исходники не тащим целиком: большие атласы ужимаются до игровых размеров.
Текстуры — белые силуэты с альфой (красятся в коде), кроме confetti —
она цветная и используется как есть.

Запуск:  py -3.10 tools/gen_fx_assets.py
После добавления новых PNG обязателен `godot --headless --import`.
"""
import os
from PIL import Image

SRC = r"E:\UnityProjects\Fish\Assets\Epic Toon FX\Textures"
DST = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "fx")

# (исходник, имя в assets/fx, целевая ширина или None = как есть)
JOBS = [
    ("star_4x4.png",         "star_4x4.png",      512),   # мультяшные звёзды-контуры
    ("lightning_v1_3x3.png", "lightning_3x3.png", 1024),  # электрические осколки
    ("confetti.png",         "confetti_3x3.png",  None),  # цветное конфетти, атлас 3x3
    ("decal_scorch.png",     "scorch.png",        None),  # выжженное пятно (белое, красится)
]


def main() -> None:
    os.makedirs(DST, exist_ok=True)
    for src_name, dst_name, width in JOBS:
        im = Image.open(os.path.join(SRC, src_name)).convert("RGBA")
        if width and im.width > width:
            h = round(im.height * width / im.width)
            im = im.resize((width, h), Image.LANCZOS)
        out = os.path.join(DST, dst_name)
        im.save(out)
        print(f"{dst_name}: {im.width}x{im.height} <- {src_name}")


if __name__ == "__main__":
    main()
