"""Ключи перевода: все Loc.t("…") из scripts/*.gd плюс строки таблиц-констант,
которые переводятся в месте показа. `py tools/loc_keys.py` печатает ключи,
которых НЕТ в scripts/LocEn.gd (пусто — перевод полный); `--all <файл>` —
выгрузить все ключи."""
import io, re, glob, sys

cyr = re.compile('[Ѐ-ӿ]')
lit = re.compile(r'"((?:[^"\\]|\\.)*)"')
call = re.compile(r'Loc\.t\("((?:[^"\\]|\\.)*)"\)')
# Таблицы-константы: файл → диапазоны строк (1-based, включительно).
TABLES = {
    'CarSelect.gd': ['DISPLAY_NAMES'],
    'TuningPanel.gd': ['SLOT_NAMES', 'SLOT_EFFECT', 'TAB_NAMES', 'FX_ROWS',
                       'FX_COLOR_NAMES', 'COLOR_NAMES', 'TIER_NAMES'],
    'Weapons.gd': ['NAMES', 'GROUP_NAMES', 'STEP_DESC'],
    'Soccer.gd': ['TEAM_NAMES'],
}


def keys():
    out = []
    for p in sorted(glob.glob('scripts/*.gd')):
        name = p.replace('\\', '/').split('/')[-1]
        if name in ('LocEn.gd', 'Loc.gd'):
            continue
        src = io.open(p, encoding='utf-8').read()
        for m in call.finditer(src):
            out.append(m.group(1))
        for const in TABLES.get(name, []):
            m = re.search(r'^const %s\b[^\n]*?:= *([\[{])' % const, src, re.M)
            if not m:
                continue
            close = ']' if m.group(1) == '[' else '}'
            depth = 0
            i = m.end() - 1
            j = i
            while j < len(src):
                if src[j] in '[{':
                    depth += 1
                elif src[j] in ']}':
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            for s in lit.findall(src[i:j]):
                if cyr.search(s):
                    out.append(s)
    seen = []
    for k in out:
        if k not in seen:
            seen.append(k)
    return seen


def have():
    try:
        src = io.open('scripts/LocEn.gd', encoding='utf-8').read()
    except IOError:
        return set()
    return set(m.group(1) for m in re.finditer(r'^\t"((?:[^"\\]|\\.)*)":', src, re.M))


if __name__ == '__main__':
    ks = keys()
    if len(sys.argv) > 2 and sys.argv[1] == '--all':
        io.open(sys.argv[2], 'w', encoding='utf-8').write('\n'.join(ks) + '\n')
        print(len(ks))
    else:
        h = have()
        miss = [k for k in ks if k not in h]
        io.open('tools/_loc_missing.txt', 'w', encoding='utf-8').write('\n'.join(miss) + '\n')
        print('keys %d, missing %d (tools/_loc_missing.txt)' % (len(ks), len(miss)))
