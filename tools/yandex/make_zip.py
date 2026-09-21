"""Архив веб-сборки для черновика Яндекс Игр: dist/web/* -> dist/DustAndFlame-yandex.zip
(index.html в корне архива). Запуск из корня проекта: py tools/yandex/make_zip.py"""
import os, zipfile
src, out = 'dist/web', 'dist/DustAndFlame-yandex.zip'
total = 0
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for name in sorted(os.listdir(src)):
        if name.endswith('.import'):
            continue
        p = os.path.join(src, name)
        total += os.path.getsize(p)
        z.write(p, name)
print('%s: %.1f MB (unpacked %.1f MB, limit 100)' % (out, os.path.getsize(out) / 1e6, total / 1e6))
