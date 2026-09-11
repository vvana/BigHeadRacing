"""Иконка запуска (ярлык игры). Источник — assets/ui/icon/icon_src.png
(картинка от игрока 10.09.2026: горящее колесо на тёмном фоне, 512x512 с
уже скруглёнными прозрачными углами).
py tools/gen_icon.py  ->  assets/ui/icon/icon_192.png, icon_fg_432.png, icon_bg_432.png

Что получается:
  icon_192      — обычная иконка (окно игры, launcher до Android 8): сама
                  картинка со своими скруглениями;
  icon_bg_432   — фон адаптивной иконки: СПЛОШНОЙ тёмный цвет, взятый с
                  краёв картинки. Систему нельзя просить не резать фон
                  (маска съедает до трети), а на однотонном срез не виден;
  icon_fg_432   — передний план: та же картинка, вписанная в FG_SIZE px.
                  Её собственный тёмный фон сливается с icon_bg_432,
                  поэтому квадрат на круглой маске не читается.

FG_SIZE — насколько крупно колесо на иконке. «Безопасная» зона Android —
288 px (66 %): всё, что за ней, маска лаунчера может срезать. 11.09 по
просьбе игрока («картинку в ярлыке сделай побольше») взято 340: колесо
заметно крупнее, а под круглой маской теряются только самые края дыма и
искр — сам диск и пламя целы (проверено отрисовкой маски).
"""
from PIL import Image, ImageDraw, ImageFilter

SRC = "assets/ui/icon/icon_src.png"
FG_SIZE = 340
OUT = "assets/ui/icon/"
src = Image.open(SRC).convert("RGBA")
if src.size != (512, 512):
    src = src.resize((512, 512), Image.LANCZOS)


def edge_color(img, band=16):
    """МЕДИАННЫЙ цвет непрозрачной рамки шириной band — фон картинки.
    Не средний: по краям пролетают искры и дым, и среднее уводит фон в
    серое, отчего квадрат переднего плана проступал бы на фоне."""
    w, h = img.size
    px = img.load()
    vals = []
    for x in range(w):
        for y in list(range(band)) + list(range(h - band, h)):
            r, g, b, a = px[x, y]
            if a > 200:
                vals.append((r, g, b))
    for y in range(h):
        for x in list(range(band)) + list(range(w - band, w)):
            r, g, b, a = px[x, y]
            if a > 200:
                vals.append((r, g, b))
    if not vals:
        return (18, 18, 20, 255)
    vals.sort(key=sum)
    r, g, b = vals[len(vals) // 2]
    return (r, g, b, 255)


bg_color = edge_color(src)
src.resize((192, 192), Image.LANCZOS).save(OUT + "icon_192.png")
Image.new("RGBA", (432, 432), bg_color).save(OUT + "icon_bg_432.png")
# Скруглённые углы картинки заливаем цветом фона: на переднем плане они
# показывали бы icon_bg_432 сквозь себя, и квадрат обводился каймой.
flat = Image.new("RGBA", src.size, bg_color)
flat.alpha_composite(src)
small = flat.resize((FG_SIZE, FG_SIZE), Image.LANCZOS)
# Края переднего плана растворяем (виньетка картинки чуть темнее фона, и
# без растушёвки её квадрат читается на однотонном icon_bg_432).
mask = Image.new("L", (FG_SIZE, FG_SIZE), 0)
ImageDraw.Draw(mask).rectangle([10, 10, FG_SIZE - 11, FG_SIZE - 11], fill=255)
small.putalpha(mask.filter(ImageFilter.GaussianBlur(9)))
fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
fg.alpha_composite(small, ((432 - FG_SIZE) // 2, (432 - FG_SIZE) // 2))
fg.save(OUT + "icon_fg_432.png")
# .ico для ярлыка Windows (все размеры, которые спрашивает проводник).
src.save(OUT + "icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48),
                                  (64, 64), (128, 128), (256, 256)])
print("ok, фон адаптивной иконки:", bg_color)
