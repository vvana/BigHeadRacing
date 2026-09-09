# Клякса масла: белая с альфой (краситься будет материалом). Похожа на референс:
# плотное неровное тело, рваные края, вытянутые брызги-«лучи», отдельные капли.
import math, random
from PIL import Image, ImageDraw, ImageFilter
random.seed(7)
S = 512
img = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(img)
cx, cy = S/2, S/2 + 6
# Тело: полигон из 180 точек с шумом нескольких частот.
pts = []
phases = [random.random()*6.28 for _ in range(6)]
for i in range(180):
    a = i/180*2*math.pi
    r = 150
    r += 22*math.sin(3*a+phases[0]) + 14*math.sin(5*a+phases[1]) + 9*math.sin(8*a+phases[2]) + 6*math.sin(13*a+phases[3])
    r *= 1.0 + 0.06*math.cos(a)  # чуть шире вправо, как в референсе
    pts.append((cx + r*math.cos(a), cy + r*math.sin(a)*0.94))
d.polygon(pts, fill=255)
# Бугры по контуру
for i in range(40):
    a = random.random()*2*math.pi
    r = 140 + random.random()*25
    rad = 12 + random.random()*22
    x, y = cx + r*math.cos(a), cy + r*math.sin(a)*0.94
    d.ellipse([x-rad, y-rad, x+rad, y+rad], fill=255)
# Лучи-брызги: тонкие вытянутые капли от края наружу, с каплей на конце.
for i in range(26):
    a = random.random()*2*math.pi
    r0 = 150 + random.random()*10
    ln = 30 + random.random()*80
    w = 3 + random.random()*7
    x0, y0 = cx + r0*math.cos(a), cy + r0*math.sin(a)*0.94
    x1, y1 = x0 + ln*math.cos(a), y0 + ln*math.sin(a)
    d.line([x0, y0, x1, y1], fill=255, width=int(w))
    rr = w*0.9 + random.random()*4
    d.ellipse([x1-rr, y1-rr, x1+rr, y1+rr], fill=255)
# Отдельные капли и мелкая крошка вокруг.
for i in range(140):
    a = random.random()*2*math.pi
    r = 175 + random.random()*70
    x, y = cx + r*math.cos(a), cy + r*math.sin(a)*0.94
    rad = 1.5 + random.random()**2*9
    if 0 < x < S and 0 < y < S:
        d.ellipse([x-rad, y-rad, x+rad, y+rad], fill=255)
img = img.filter(ImageFilter.GaussianBlur(0.8))
alpha = img.point(lambda v: 255 if v > 128 else (v*2 if v > 64 else 0))
out = Image.new("RGBA", (S, S), (255, 255, 255, 0))
out.putalpha(alpha)
out.save(r"E:\UnityProjects\BigHeadRacing\assets\fx\oil_splat.png")
# Маска 48x48: бит = альфа > 128 в центре клетки (с небольшим сжатием, чтобы
# срабатывало только по телу и крупным брызгам, не по крошке).
N = 48
small = alpha.resize((N, N), Image.BOX)
bits = []
for y in range(N):
    for x in range(N):
        bits.append(1 if small.getpixel((x, y)) > 110 else 0)
by = bytearray()
for i in range(0, len(bits), 8):
    v = 0
    for b in range(8):
        v |= bits[i+b] << (7-b)
    by.append(v)
print("HEX", by.hex())
print("fill", sum(bits)/len(bits))
for y in range(0, N, 2):
    print("".join("#" if bits[y*N+x] else "." for x in range(N)))
