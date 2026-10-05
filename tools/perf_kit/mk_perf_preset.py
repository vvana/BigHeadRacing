# Временный пресет «Android (perf)» для замерной сборки: копия «Android (test)»
# с другим пакетом, без gradle, со стендом замера вместо гаража.
# Исходный export_presets.cfg сохраняется рядом и возвращается после экспорта.
import io, re, shutil, sys

SRC = r'E:\UnityProjects\BigHeadRacing\export_presets.cfg'
KEEP = r'E:\UnityProjects\BigHeadRacing\tools\perf_kit\export_presets.cfg.orig'

if sys.argv[1] == 'make':
    shutil.copyfile(SRC, KEEP)
    raw = io.open(SRC, 'rb').read()
    nl = b'\r\n' if b'\r\n' in raw else b'\n'
    s = raw.decode('utf-8').replace('\r\n', '\n')
    a = s.index('[preset.3]')
    b = s.index('[preset.4]')
    blk = s[a:b]
    n = len(re.findall(r'^\[preset\.\d+\]$', s, re.M))
    blk = blk.replace('[preset.3]', '[preset.%d]' % n).replace('[preset.3.options]', '[preset.%d.options]' % n)
    blk = blk.replace('name="Android (test)"', 'name="Android (perf)"')
    blk = blk.replace('export_path="dist/test/DustAndFlame.apk"', 'export_path="tools/perf_kit/perf.apk"')
    pass
    blk = blk.replace('package/unique_name="ru.dustandflame.game.test"', 'package/unique_name="ru.dustandflame.game.perf"')
    blk = blk.replace('package/name="Пыль и Пламя ТЕСТ"', 'package/name="Пыль Замер"')
    blk = blk.replace('command_line/extra_args=""', 'command_line/extra_args="res://tools/MeasurePerf.tscn"')
    assert 'perf' in blk and 'MeasurePerf' in blk
    if not s.endswith('\n'):
        s += '\n'
    out = s + ('' if s.endswith('\n\n') else '\n') + blk
    io.open(SRC, 'wb').write(out.replace('\n', nl.decode()).encode('utf-8'))
    print('preset', n, 'added')
else:
    import time
    for k in range(20):
        try:
            shutil.copyfile(KEEP, SRC)
            print('restored')
            break
        except OSError:
            time.sleep(1)

