# -*- coding: utf-8 -*-
"""Логотип-название «ПЫЛЬ И ПЛАМЯ» под стиль ключевого арта (11.09.2026).

py tools/gen_logo.py  ->  assets/ui/logo_title.png

Игрок прислал ключевой арт, где название набрано тяжёлым узким курсивом с
заливкой «жёлтое сверху — красное снизу» и чёрной обводкой, и попросил
написать название в игре тем же шрифтом. Самого шрифта у нас нет (арт
рисовала нейросеть, файла шрифта к нему не прилагается, качать со стороны
я не могу), поэтому надпись СОБИРАЕТСЯ: ближайшее по рисунку начертание из
системных — Impact (узкий гротеск с плотными штрихами), наклон 0.26 даёт
курсив, дальше — та же градиентная заливка, обводка и мягкая тень.

ВАЖНО: в игру уезжает только КАРТИНКА (PNG), файл шрифта никуда не
копируется и в сборку не попадает — Impact остаётся на машине, где
картинку нарисовали. Нужен полностью свободный шрифт — поставьте
FONT = Russo One (лежит в assets/ui, лицензия OFL), рисунок станет шире и
округлее, но пересобирать ничего больше не придётся.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# Прописными, хотя на арте название строчными: табличка в гараже узкая
# (268×46), и у строчных высота буквы вдвое меньше — с телефона не
# прочесть. Захотите «пыль и пламя» как на арте — поменяйте эту строку.
TEXT = "ПЫЛЬ И ПЛАМЯ"
FONT = "C:/Windows/Fonts/impact.ttf"
OUT = "assets/ui/logo_title.png"
SIZE = 160          # кегль до уменьшения
SS = 4              # во столько раз рисуем крупнее ради сглаживания
SKEW = 0.24         # наклон курсива (сдвиг верха вправо, доля высоты)
RIM = 3             # тонкая светлая кайма вокруг букв (есть на арте)
OUTLINE = 7         # тёмная обводка поверх каймы, px итоговой картинки
# Заливка — цвета СНЯТЫ ПИПЕТКОЙ с арта (photo_2026-09-11_08-44-44.jpg,
# вертикальный разрез по букве «d»): сверху светлое золото, к низу красное.
STOPS = [(0.00, (255, 243, 148)), (0.22, (255, 200, 22)),
         (0.50, (246, 130, 9)), (0.78, (225, 28, 9)),
         (1.00, (168, 5, 0))]
RIM_COLOR = (255, 232, 150, 255)    # кайма — светлое золото, как на арте
INK_COLOR = (8, 12, 34, 255)        # обводка не чёрная, а тёмно-синяя


def gradient(w: int, h: int) -> Image.Image:
    g = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(g)
    for y in range(h):
        t = y / max(1, h - 1)
        for i in range(len(STOPS) - 1):
            a, ca = STOPS[i]
            b, cb = STOPS[i + 1]
            if a <= t <= b:
                k = (t - a) / (b - a)
                c = tuple(int(ca[j] + (cb[j] - ca[j]) * k) for j in range(3))
                break
        d.line([(0, y), (w, y)], fill=c + (255,))
    return g


def shear(mask: Image.Image, k: float) -> Image.Image:
    """Наклон вправо: верх уезжает на k*высоту, низ остаётся на месте."""
    w, h = mask.size
    dx = int(h * k)
    out = mask.transform((w + dx, h), Image.AFFINE, (1, k, -k * h, 0, 1, 0),
                         resample=Image.BICUBIC)
    return out


font = ImageFont.truetype(FONT, SIZE * SS)
probe = Image.new("L", (SIZE * SS * 24, SIZE * SS * 3), 0)
ImageDraw.Draw(probe).text((SIZE * SS, SIZE * SS), TEXT, font=font, fill=255)
mask = shear(probe.crop(probe.getbbox()), SKEW)

pad = (RIM + OUTLINE + 10) * SS
w, h = mask.size[0] + pad * 2, mask.size[1] + pad * 2
body_mask = Image.new("L", (w, h), 0)
body_mask.paste(mask, (pad, pad))

# Кайма и обводка — расширения маски (MaxFilter требует нечётное ядро).
def grow(mask: Image.Image, r: int) -> Image.Image:
    return mask.filter(ImageFilter.MaxFilter(r * 2 * SS + 1))


rim = grow(body_mask, RIM)
edge = grow(body_mask, RIM + OUTLINE)
canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
# Мягкая тень вниз: на белой эмали таблички даёт тот же объём, что на арте.
shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
shadow.paste((6, 10, 30, 200), (0, 0), edge)
canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(4 * SS)),
                       (0, 4 * SS))
canvas.paste(INK_COLOR, (0, 0), edge)
canvas.paste(RIM_COLOR, (0, 0), rim)
canvas.paste(gradient(w, h), (0, 0), body_mask)

canvas = canvas.crop(canvas.getbbox())
canvas = canvas.resize((canvas.width // SS, canvas.height // SS), Image.LANCZOS)
canvas.save(OUT)
print("ok", OUT, canvas.size)
