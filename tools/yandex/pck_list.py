import struct, sys, collections, os
p = sys.argv[1]
f = open(p, 'rb')
assert f.read(4) == b'GDPC'
ver, = struct.unpack('<I', f.read(4))
f.read(12)  # godot version
flags, = struct.unpack('<I', f.read(4))
base, = struct.unpack('<Q', f.read(8))
f.read(16 * 4)
n, = struct.unpack('<I', f.read(4))
files = []
for _ in range(n):
    l, = struct.unpack('<I', f.read(4))
    path = f.read(l).rstrip(b'\0').decode('utf-8', 'replace')
    off, size = struct.unpack('<QQ', f.read(16))
    f.read(16 + 4)
    files.append((path, size))
files.sort(key=lambda x: -x[1])
tot = sum(s for _, s in files)
print('files', n, 'total', tot)
print('--- top 40')
for path, s in files[:40]:
    print('%10d  %s' % (s, path))
print('--- by ext')
by = collections.Counter()
for path, s in files:
    by[os.path.splitext(path)[1]] += s
for e, s in by.most_common(15):
    print('%10d  %s' % (s, e))
print('--- by top dir')
bd = collections.Counter()
for path, s in files:
    parts = path.replace('res://', '').split('/')
    bd['/'.join(parts[:2]) if parts[0] in ('assets', '.godot') else parts[0]] += s
for d, s in bd.most_common(20):
    print('%10d  %s' % (s, d))
