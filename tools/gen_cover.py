# -*- coding: utf-8 -*-
"""Обложки карточки Яндекс Игр (17.09.2026).

py tools/gen_cover.py  ->  dist/yandex/cover_800x470.png     (обязательная)
                           dist/yandex/cover_1560x520.png    (на витрину)
                           dist/yandex/icon_512.png          (копия иконки)

Площадка запрещает ставить на обложку скриншот игры (п. 5.6) и любые
элементы игрового интерфейса (п. 8.3.4), а также рамки и скруглённые углы
(п. 8.3.3). Поэтому обложка собирается из РЕНДЕРОВ машин на прозрачном
фоне (tools/ShotCover.tscn) на нарисованном закатном фоне, сверху — та же
надпись «Пыль и Пламя», что и на экране загрузки игры (п. 5.1.3: название
обязано совпадать во всех материалах).

Рисуем с трёхкратным запасом и уменьшаем — так у машин и надписи чистые
края без «лесенки».
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

CARS = "tools/shots_yx/cover2"
LOGO = "assets/ui/logo_title.png"
ICON = "dist/store/icon_512.png"
OUT = "dist/yandex"
SS = 3  # суперсэмплинг

# Кто едет на обложке: (файл рендера, доля высоты холста, центр по X, центр по Y)
CAST = [
    ("car_vz05r_yellow-l1.png", 0.28, 0.20, 0.76),
    ("car_ac2-cyan2-w8-e3-s2.png", 0.29, 0.80, 0.765),
    ("car_ac1-red2-w3-e5-s4-x2.png", 0.38, 0.50, 0.79),
]


def sky(w: int, h: int) -> Image.Image:
    """Закат: фиолетовый верх, оранжевое зарево у горизонта, тёмная земля."""
    stops = [
        (0.00, (26, 18, 58)),
        (0.30, (86, 30, 78)),
        (0.52, (196, 58, 48)),
        (0.66, (255, 150, 48)),
        (0.72, (92, 44, 42)),
        (1.00, (20, 14, 22)),
    ]
    ys = np.linspace(0.0, 1.0, h)
    col = np.zeros((h, 3))
    for i in range(len(stops) - 1):
        y0, c0 = stops[i]
        y1, c1 = stops[i + 1]
        m = (ys >= y0) & (ys <= y1)
        t = ((ys[m] - y0) / (y1 - y0))[:, None]
        col[m] = np.array(c0) * (1 - t) + np.array(c1) * t
    img = np.repeat(col[:, None, :], w, axis=1)

    # Зарево у горизонта — мягкое пятно, ради него машины читаются силуэтом.
    xx, yy = np.meshgrid(np.linspace(0, 1, w), np.linspace(0, 1, h))
    glow = np.exp(-(((xx - 0.5) / 0.42) ** 2 + ((yy - 0.66) / 0.16) ** 2))
    img += glow[:, :, None] * np.array([90, 46, 10])
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")


def speed_rays(w: int, h: int) -> Image.Image:
    """Клинья света от горизонта — ощущение скорости, без единой буквы."""
    lay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    cx, cy = w * 0.5, h * 0.66
    rng = np.random.default_rng(17092026)
    for k in range(26):
        a = rng.uniform(-3.05, -0.09)          # веер вверх
        spread = rng.uniform(0.006, 0.03)
        length = rng.uniform(0.6, 1.5) * w
        alpha = int(rng.uniform(14, 46))
        p1 = (cx + np.cos(a - spread) * length, cy + np.sin(a - spread) * length)
        p2 = (cx + np.cos(a + spread) * length, cy + np.sin(a + spread) * length)
        d.polygon([(cx, cy), p1, p2], fill=(255, 214, 150, alpha))
    return lay.filter(ImageFilter.GaussianBlur(w * 0.012))


def dust(w: int, h: int) -> Image.Image:
    """Пыль из-под колёс — светлые клубы над землёй."""
    lay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    rng = np.random.default_rng(1709)
    for k in range(70):
        x = rng.uniform(-0.05, 1.05) * w
        y = rng.normal(0.79, 0.07) * h
        r = rng.uniform(0.02, 0.085) * w
        a = int(rng.uniform(18, 60))
        d.ellipse([x - r, y - r * 0.55, x + r, y + r * 0.55],
                  fill=(255, 208, 150, a))
    return lay.filter(ImageFilter.GaussianBlur(w * 0.02))


def put_car(canvas: Image.Image, path: str, frac: float, cx: float, cy: float) -> None:
    """Машина с мягкой тенью под ней; cx/cy — доли ширины и высоты."""
    im = Image.open(os.path.join(CARS, path)).convert("RGBA")
    im = im.crop(im.getbbox())
    w = int(canvas.width * frac * im.width / im.height * 0.62)
    h = int(w * im.height / im.width)
    im = im.resize((w, h), Image.LANCZOS)

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sx, sy = canvas.width * cx, canvas.height * cy + h * 0.30
    sd.ellipse([sx - w * 0.46, sy - h * 0.13, sx + w * 0.46, sy + h * 0.13],
               fill=(0, 0, 0, 150))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(w * 0.05)))
    canvas.alpha_composite(im, (int(canvas.width * cx - w / 2),
                                int(canvas.height * cy - h / 2)))


def put_logo(canvas: Image.Image, width_frac: float, cy: float) -> None:
    logo = Image.open(LOGO).convert("RGBA")
    w = int(canvas.width * width_frac)
    h = int(w * logo.height / logo.width)
    logo = logo.resize((w, h), Image.LANCZOS)
    x = int((canvas.width - w) / 2)
    y = int(canvas.height * cy - h / 2)

    # Тёмное сияние под надписью: буквы с обводкой читаются на любом фоне.
    halo = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    halo.paste((0, 0, 0, 190), (x, y, x + w, y + h), logo.split()[3])
    canvas.alpha_composite(halo.filter(ImageFilter.GaussianBlur(w * 0.03)))
    canvas.alpha_composite(logo, (x, y))


def build(w: int, h: int, logo_frac: float, logo_y: float,
          cast: list) -> Image.Image:
    W, H = w * SS, h * SS
    canvas = sky(W, H).convert("RGBA")
    canvas.alpha_composite(speed_rays(W, H))
    for path, frac, cx, cy in cast:
        put_car(canvas, path, frac, cx, cy)
    canvas.alpha_composite(dust(W, H))
    put_logo(canvas, logo_frac, logo_y)
    return canvas.convert("RGB").resize((w, h), Image.LANCZOS)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    cover = build(800, 470, 0.66, 0.20, CAST)
    cover.save(os.path.join(OUT, "cover_800x470.png"))

    # Витринная обложка шире и ниже — машины расходятся к краям. Размер
    # машины в put_car считается от ШИРИНЫ холста, поэтому доли тут мельче.
    wide = [
        ("car_vz05r_yellow-l1.png", 0.15, 0.24, 0.70),
        ("car_ac2-cyan2-w8-e3-s2.png", 0.155, 0.76, 0.705),
        ("car_ac1-red2-w3-e5-s4-x2.png", 0.20, 0.50, 0.73),
    ]
    build(1560, 520, 0.40, 0.19, wide).save(
        os.path.join(OUT, "cover_1560x520.png"))

    Image.open(ICON).convert("RGB").save(os.path.join(OUT, "icon_512.png"))
    for f in ("cover_800x470.png", "cover_1560x520.png", "icon_512.png"):
        im = Image.open(os.path.join(OUT, f))
        print(f, im.size, im.mode,
              "%.0f КБ" % (os.path.getsize(os.path.join(OUT, f)) / 1024))


if __name__ == "__main__":
    main()
