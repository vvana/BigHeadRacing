# -*- coding: utf-8 -*-
"""Обложки Яндекс Игр из присланного арта (18.09.2026).

py tools/gen_cover_art.py  ->  dist/yandex/cover_800x470.png     (обязательная)
                               dist/yandex/cover_1560x520.png    (на витрину)

Исходник — tools/shots_yx/cover_art.jpg (1248×832, ИИ-арт игрока: ночной
неоновый город, машины с оружием). Прежние обложки из рендеров машин
(gen_cover.py) сохраняются рядом с суффиксом _render — запасной вариант,
если модерация сочтёт арт «не имеющим отношения к игре» (п. 5.1.1).

Название на обложке обязано совпадать с игрой (п. 5.1.3) — накладываем ту
же надпись, что на экране загрузки (assets/ui/logo_title.png). Рамок и
скруглений нет (п. 8.3.3), интерфейса игры нет (п. 8.3.4).
"""
import os
import shutil
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

ART = "tools/shots_yx/cover_art.jpg"
LOGO = "assets/ui/logo_title.png"
OUT = "dist/yandex"
SS = 2  # суперсэмплинг ради чистых краёв надписи


def put_logo(canvas: Image.Image, cx: float, cy: float, width: int) -> None:
    """Надпись с тёмным сиянием под ней — читается поверх неона и вывесок."""
    logo = Image.open(LOGO).convert("RGBA")
    h = int(width * logo.height / logo.width)
    logo = logo.resize((width, h), Image.LANCZOS)
    x, y = int(cx - width / 2), int(cy - h / 2)
    halo = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    halo.paste((0, 0, 0, 230), (x, y, x + width, y + h), logo.split()[3])
    canvas.alpha_composite(halo.filter(ImageFilter.GaussianBlur(width * 0.035)))
    canvas.alpha_composite(halo.filter(ImageFilter.GaussianBlur(width * 0.012)))
    canvas.alpha_composite(logo, (x, y))


def cover_800x470() -> Image.Image:
    """Кадрируем арт под 800×470: режем небо сверху (там только вывески),
    низ с выхлопом жёлтой машины оставляем. Надпись — вверху по центру."""
    W, H = 800 * SS, 470 * SS
    art = Image.open(ART).convert("RGB")
    crop_h = int(art.width * H / W)
    top = int((art.height - crop_h) * 0.72)   # больше срезаем сверху
    art = art.crop((0, top, art.width, top + crop_h)).resize((W, H), Image.LANCZOS)
    canvas = art.convert("RGBA")
    # Лёгкое затемнение верхней кромки, чтобы надпись не спорила с вывесками.
    shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(shade)
    for i in range(int(H * 0.36)):
        a = int(120 * (1 - i / (H * 0.36)) ** 1.5)
        d.line([(0, i), (W, i)], fill=(6, 4, 20, a))
    canvas.alpha_composite(shade)
    put_logo(canvas, W / 2, H * 0.145, int(W * 0.6))   # не наезжать на пушки
    return canvas.convert("RGB").resize((800, 470), Image.LANCZOS)


def cover_1560x520() -> Image.Image:
    """Витрина 3:1: арт целиком (по высоте) слева, справа — его же размытое
    продолжение в тех же неоновых тонах и крупная надпись. Так ни одна
    машина не режется, а баннер читается как афиша."""
    W, H = 1560 * SS, 520 * SS
    art = Image.open(ART).convert("RGB")
    art_w = int(art.width * H / art.height)
    art = art.resize((art_w, H), Image.LANCZOS)

    # Фон правой части: растянутая правая треть арта, сильно размытая и
    # притемнённая — цвета продолжаются, детали не отвлекают от надписи.
    strip = art.crop((int(art_w * 0.6), 0, art_w, H)).resize((W - art_w + 200, H))
    strip = strip.filter(ImageFilter.GaussianBlur(H * 0.06))
    strip = ImageEnhance.Brightness(strip).enhance(0.45)
    canvas = Image.new("RGBA", (W, H), (10, 8, 28, 255))
    canvas.paste(strip, (art_w - 200, 0))
    canvas.paste(art, (0, 0))

    # Мягкий переход арт → фон: на правом краю арта плавная тень.
    fade_w = int(art_w * 0.22)
    fade = Image.new("RGBA", (fade_w, H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fade)
    for i in range(fade_w):
        t = i / fade_w
        fd.line([(i, 0), (i, H)], fill=(10, 8, 28, int(255 * t ** 1.6)))
    canvas.alpha_composite(fade, (art_w - fade_w, 0))
    # ...и дальше сплошной фон, чтобы кромка арта не читалась.
    canvas.alpha_composite(
        Image.new("RGBA", (W - art_w, H), (10, 8, 28, 0)), (art_w, 0))

    right_cx = art_w * 0.9 + (W - art_w * 0.9) / 2
    put_logo(canvas, right_cx, H * 0.5, int((W - art_w * 0.9) * 0.86))
    return canvas.convert("RGB").resize((1560, 520), Image.LANCZOS)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for name in ("cover_800x470.png", "cover_1560x520.png"):
        src = os.path.join(OUT, name)
        dst = os.path.join(OUT, name.replace(".png", "_render.png"))
        if os.path.exists(src) and not os.path.exists(dst):
            shutil.move(src, dst)   # старый вариант из рендеров — в запас
    cover_800x470().save(os.path.join(OUT, "cover_800x470.png"))
    cover_1560x520().save(os.path.join(OUT, "cover_1560x520.png"))
    for f in ("cover_800x470.png", "cover_1560x520.png"):
        p = os.path.join(OUT, f)
        im = Image.open(p)
        print(f, im.size, im.mode, "%.0f KB" % (os.path.getsize(p) / 1024))


if __name__ == "__main__":
    main()
