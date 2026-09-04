# -*- coding: utf-8 -*-
# Симуляция экономики BHR v2 (04.09.2026): общие детали, 4 слота у всех (Unity — 3),
# 3 улучшения на оружие.
XP_H = 750.0
COIN_H_ADS = 7800.0   # заезды 4800 + реклама 3000
COIN_H_NOADS = 4800.0
LEVEL_MONEY = 200

def xp_to(n):  # опыт, нужный чтобы с уровня n перейти на n+1
    return 40*n + 60

CARS = {  # база: (уровень, цена, слотов: Unity 3 без колёс, остальные 4)
 "vz03":(2,600,4),"vz04":(3,1200,4),"vz05":(4,2000,4),"ac1":(5,3000,4),
 "vz06":(6,4000,4),"vz07":(7,5500,4),"ac2":(8,7000,4),"vz05r":(9,9000,4),
 "vz08":(10,11000,4),"ac3":(11,13500,4),"vz09":(12,16000,4),"vz099":(13,19000,4),
 "ac4":(14,22000,4),"gz21":(15,25000,4),"gz24":(16,29000,4),"ac5":(17,33000,4),
 "vz31":(18,37000,4),"fastback":(19,41000,3),"ac6":(20,46000,4),"safari":(21,50000,3),
 "chevelle":(22,55000,3),"ac7":(23,60000,4),"godfather":(24,65000,3),"lemans":(25,70000,3),
 "ac8":(26,76000,4),"superbird":(27,82000,3),"dragster":(28,88000,3),"diablo":(30,95000,3),
}
# Детали: номер → (уровень, цена). Общие на все машины. Колёса №1 — сток.
PARTS = {1:(1,150),2:(2,300),3:(3,600),4:(5,1000),5:(8,1600),6:(10,2500),
         7:(13,4000),8:(17,6000),9:(21,9000),10:(25,13000)}
SLOTS = 4
# Оружие: группа → (список видов, [(ур, цена)×3])
WEAPONS = {
 "A": (["Мина","Масло","Ускорение"], [(3,500),(7,1500),(14,4000)]),
 "B": (["Магнит","Заморозка","Глушилка"], [(4,800),(9,2500),(18,6500)]),
 "C": (["Ракета","Лазер","Авиаудар"], [(6,1200),(11,4000),(22,10000)]),
}
# Косметика аркадных (% от цены машины): 10 наклеек + полоса по 2 %, металлик 12 цветов по 3.5 %
def arcade_cosm(price):
    st = max(30, round(price*0.02/10)*10)
    mt = max(50, round(price*0.035/10)*10)
    return 11*st + 12*mt

items = []  # (уровень, цена, категория, имя)
for b,(l,p,s) in CARS.items(): items.append((l,p,"car",b))
for n,(l,p) in PARTS.items():
    for slot in ["wheel","engine","spoiler","exhaust"]:
        if slot=="wheel" and n==1: continue
        items.append((l,p,"part","%s:%d"%(slot,n)))
for g,(names,steps) in WEAPONS.items():
    for w in names:
        for i,(l,p) in enumerate(steps): items.append((l,p,"weapon","%s ст.%d"%(w,i+1)))
for b,(l,p,s) in CARS.items():
    if b.startswith("ac"): items.append((l,arcade_cosm(p),"cosm",b+" наклейки+металлик"))

def total(cat=None):
    return sum(p for l,p,c,n in items if cat is None or c==cat)
print("ИТОГО: машины %d, детали %d, оружие %d, косметика аркадных %d, всё %d" % (
    total("car"),total("part"),total("weapon"),total("cosm"),total()))
print("Игровое (машины+оружие): %d; c деталями: %d" % (total("car")+total("weapon"), total("car")+total("weapon")+total("part")))

# --- по уровням: что открывается, сколько стоит, сколько заработано за уровень
print("\nУр | часов | заработано за уровень (с рекл.) | открылось на сумму | накоп. открыто | накоп. заработано | что")
lvl=1; hours=0.0; earned=LEVEL_MONEY*0; cum_open=0
rows=[]
for lvl in range(1,31):
    opened=[(p,c,n) for l,p,c,n in items if l==lvl]
    val=sum(p for p,c,n in opened); cum_open+=val
    if lvl==1: dt=0; e=0
    else:
        dt=xp_to(lvl-1)/XP_H; e=dt*COIN_H_ADS+LEVEL_MONEY*lvl
    hours+=dt; earned+=e
    desc=", ".join(n for p,c,n in opened if c in("car",))+ (" | деталей №%s"%",".join(sorted(set(n.split(":")[1] for p,c,n in opened if c=="part"))) if any(c=="part" for p,c,n in opened) else "") + (" | оружие: "+", ".join(n for p,c,n in opened if c=="weapon") if any(c=="weapon" for p,c,n in opened) else "")
    print("%2d | %5.1f | %7.0f | %7.0f | %8.0f | %8.0f | %.2f | %s" % (lvl,hours,e,val,cum_open,earned, cum_open/max(1,earned), desc))

# --- по часам
print("\nЧасов | уровень | монет с рекламой | без рекламы | открыто контента")
def state(h, rate):
    xp=h*XP_H; lvl=1; money=h*rate
    while xp>=xp_to(lvl): xp-=xp_to(lvl); lvl+=1; money+=LEVEL_MONEY*lvl
    return lvl, money
for h in [0.5,1,2,3,5,8,12,15,20,25,30,40,50,80,100,135,180]:
    l,m=state(h,COIN_H_ADS); l2,m2=state(h,COIN_H_NOADS)
    op=sum(p for lv,p,c,n in items if lv<=l)
    print("%5.1f | %2d | %8.0f | %8.0f | %8.0f" % (h,l,m,m2,op))
# нормальный путь
path = 600+3000+11000+22000+33000+46000+95000
parts = (150+300+600+1000+1600+2500+4000+6000)*4-150
weap = 15200+6000+9800
cosm = arcade_cosm(46000)//2
tot=path+parts+weap+cosm
print("\nНормальный путь: машины %d + детали до №8 %d + 3 ветки оружия %d + косметика %d = %d" % (path,parts,weap,cosm,tot))
for rate,name in [(COIN_H_ADS,"с рекламой"),(COIN_H_NOADS,"без")]:
    h=0.0
    while state(h,rate)[1]<tot: h+=0.5
    print("  %s: %.0f ч (уровень %d)"%(name,h,state(h,rate)[0]))
for name,val in [("всё игровое (машины+оружие)",total("car")+total("weapon")),("игровое+детали",total("car")+total("weapon")+total("part")),("всё",total())]:
    for rate,rn in [(COIN_H_ADS,"с рекламой"),(COIN_H_NOADS,"без")]:
        h=0.0
        while state(h,rate)[1]<val: h+=1
        print("  %s %s: %d ч"%(name,rn,h))
