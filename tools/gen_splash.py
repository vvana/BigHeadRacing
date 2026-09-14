# -*- coding: utf-8 -*-
"""Экран загрузки с названием игры (11.09.2026).

py tools/gen_splash.py  ->  assets/ui/splash.png
                            dist/store/icon_512.png

До этого при запуске игра показывала логотип Godot — единственное место,
где вместо «Пыли и Пламени» стоял чужой бренд (заметно и в магазине, и на
телефоне). Собираем свой: горящее колесо из иконки (assets/ui/icon/
icon_src.png) и под ним готовая надпись-логотип (assets/ui/logo_title.png,
её рисует gen_logo.py). Фон прозрачный — его заливает сам Godot цветом
application/boot_splash/bg_color.

Заодно готовим квадратную иконку 512x512 для карточки в магазине (RuStore
просит именно такую) — она в игру не входит, лежит в dist/store/.
"""
import os
from PIL import Image

SRC_ICON = "assets/ui/icon/icon_src.png"
SRC_LOGO = "assets/ui/logo_title.png"
OUT_SPLASH = "assets/ui/splash.png"
OUT_STORE = "dist/store/icon_512.png"

W, H = 1024, 640          # холст экрана загрузки
WHEEL = 340               # сторона колеса
GAP = 28                  # просвет между колесом и надписью
LOGO_W = 820              # ширина надписи


def _fit(img: Image.Image, box: int) -> Image.Image:
    """Вписать картинку в квадрат box, сохранив пропорции."""
    k = box / max(img.width, img.height)
    return img.resize((max(1, int(img.width * k)), max(1, int(img.height * k))),
                      Image.LANCZOS)


def main() -> None:
    wheel = Image.open(SRC_ICON).convert("RGBA")
    logo = Image.open(SRC_LOGO).convert("RGBA")

    # --- экран загрузки ---
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    w = _fit(wheel, WHEEL)
    logo_h = max(1, int(logo.height * LOGO_W / logo.width))
    logo_s = logo.resize((LOGO_W, logo_h), Image.LANCZOS)
    block_h = w.height + GAP + logo_h
    top = (H - block_h) // 2
    canvas.alpha_composite(w, ((W - w.width) // 2, top))
    canvas.alpha_composite(logo_s, ((W - LOGO_W) // 2, top + w.height + GAP))
    canvas.save(OUT_SPLASH)
    print("%s — %dx%d" % (OUT_SPLASH, canvas.width, canvas.height))

    # --- иконка для карточки магазина ---
    os.makedirs(os.path.dirname(OUT_STORE), exist_ok=True)
    side = min(wheel.width, wheel.height)
    square = wheel.crop(((wheel.width - side) // 2, (wheel.height - side) // 2,
                         (wheel.width + side) // 2, (wheel.height + side) // 2))
    store = Image.new("RGBA", (512, 512), (27, 27, 27, 255))
    store.alpha_composite(square.resize((512, 512), Image.LANCZOS))
    store.convert("RGB").save(OUT_STORE)
    print("%s — 512x512, непрозрачная (в игру не входит)" % OUT_STORE)


if __name__ == "__main__":
    main()
