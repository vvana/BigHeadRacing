import io
def patch(p, reps):
    s=io.open(p,encoding='utf-8',newline='').read()
    for a,b in reps:
        done=False
        for nl in ('\r\n','\n'):
            aa=a.replace('\n',nl); bb=b.replace('\n',nl)
            if s.count(aa)==1:
                s=s.replace(aa,bb); done=True; break
        assert done,(p,a[:50],s.count(a.replace('\n','\r\n')),s.count(a))
    io.open(p,'w',encoding='utf-8',newline='').write(s)
    print('patched',p)
patch('scripts/Car.gd',[
('''			# II ступень — ДВЕ мины, под левое и правое колесо (спецификация
			# игрока 04.09); I — взрыв шире на 15 %.
			var right := Vector3(-fwd.z, 0.0, fwd.x)
			var offsets: Array[float] = [0.0]
			if step >= 2:
				offsets = [-0.8, 0.8]''',
'''			# II ступень — ДВЕ мины, под левое и правое колесо (спецификация
			# игрока 04.09); I — взрыв шире на 15 %; III — ТРИ мины в ряд
			# (просьба 09.09).
			var right := Vector3(-fwd.z, 0.0, fwd.x)
			var offsets: Array[float] = [0.0]
			if step >= 3:
				offsets = [-1.0, 0.0, 1.0]
			elif step >= 2:
				offsets = [-0.8, 0.8]'''),
('''			if p.freeze:
				p.freeze_time = 3.45 if step >= 1 else 3.0
				p.speed_mult = 1.2 if step >= 2 else 1.0''',
'''			if p.freeze:
				# III — заморозка ещё на 1 с дольше (просьба 09.09).
				p.freeze_time = (3.45 if step >= 1 else 3.0) \
						+ (1.0 if step >= 3 else 0.0)
				p.speed_mult = 1.2 if step >= 2 else 1.0'''),
('''			# I — пятно крупнее; заносить и крутить масло начинает со II
			# ступени, ниже — только замедляет (спецификация игрока 04.09).
			oil.size_mult = 1.15 if step >= 1 else 1.0''',
'''			# I — пятно крупнее; заносить и крутить масло начинает со II
			# ступени, ниже — только замедляет (спецификация игрока 04.09);
			# III — пятно ещё больше (×1.4, просьба 09.09).
			oil.size_mult = 1.4 if step >= 3 else (1.15 if step >= 1 else 1.0)'''),
('''			# Ступени: I — сбитое управление дольше, II — волна быстрее.
			w.stun_time = ScrambleWave.SCRAMBLE_TIME * (1.15 if step >= 1 else 1.0)''',
'''			# Ступени: I — сбитое управление дольше, II — волна быстрее,
			# III — ещё на 1 с дольше (просьба 09.09).
			w.stun_time = ScrambleWave.SCRAMBLE_TIME * (1.15 if step >= 1 else 1.0) \
					+ (1.0 if step >= 3 else 0.0)'''),
('''		# Ступени магнита (08.09): I — рывок сильнее на 15 %; II — жертвы
		# теряют ВСЮ скорость (спецификация игрока 04.09).
		var mstep := wstep(Weapons.MAGNET)
		var power: float = lerpf(MAGNET_PULL, MAGNET_FAR, t) * wear \
				* (1.15 if mstep >= 1 else 1.0)''',
'''		# Ступени магнита (08.09): I — рывок сильнее на 15 %; II — жертвы
		# теряют ВСЮ скорость (спецификация игрока 04.09); III — ОТДЁРГИВАЕТ
		# И ОСТАНАВЛИВАЕТ (просьба 09.09): рывок к магниту в полтора раза
		# сильнее, а через MAGNET_STOP_DELAY скорость жертвы обнуляется —
		# её дёрнуло назад и она встала.
		var mstep := wstep(Weapons.MAGNET)
		var power: float = lerpf(MAGNET_PULL, MAGNET_FAR, t) * wear \
				* (1.5 if mstep >= 3 else (1.15 if mstep >= 1 else 1.0))'''),
('''		other.push_from_blast(pull_dir, power, spin, 0.12)
		other.show_effect_icon(Weapons.MAGNET, MAGNET_ICON_TIME)''',
'''		other.push_from_blast(pull_dir, power, spin, 0.12)
		if mstep >= 3:
			get_tree().create_timer(MAGNET_STOP_DELAY).timeout.connect(
					func() -> void:
						if is_instance_valid(other) and other.alive:
							other.apply_speed_cut(0.0))
		other.show_effect_icon(Weapons.MAGNET, MAGNET_ICON_TIME)'''),
('''	const MAGNET_ICON_TIME := 1.5 # сколько над жертвой висит значок магнита''',
'''	const MAGNET_ICON_TIME := 1.5 # сколько над жертвой висит значок магнита
	const MAGNET_STOP_DELAY := 0.4 # III: через столько после рывка жертва встаёт'''),
])
patch('scripts/Main.gd',[
('''			var offsets: Array[float] = [0.0]
			if step >= 2:
				offsets = [-0.8, 0.8]
			for sx: float in offsets:
				var m := Mine.new()
				m.inert = true''',
'''			var offsets: Array[float] = [0.0]
			if step >= 3:
				offsets = [-1.0, 0.0, 1.0]
			elif step >= 2:
				offsets = [-0.8, 0.8]
			for sx: float in offsets:
				var m := Mine.new()
				m.inert = true'''),
('''			oil.inert = true
			oil.size_mult = 1.15 if step >= 1 else 1.0''',
'''			oil.inert = true
			oil.size_mult = 1.4 if step >= 3 else (1.15 if step >= 1 else 1.0)'''),
])
patch('scripts/Weapons.gd',[
('''			"две мины — под левое и правое колесо",
			"высшая ступень"],''','''			"две мины — под левое и правое колесо",
			"три мины в ряд"],'''),
('''			"наехавшего заносит и крутит (без II — только замедляет)",
			"высшая ступень"],''','''			"наехавшего заносит и крутит (без II — только замедляет)",
			"пятно ещё больше"],'''),
('''			"жертвы теряют всю скорость",
			"высшая ступень"],''','''			"жертвы теряют всю скорость",
			"отдёргивает к себе и останавливает"],'''),
('''			"ледышка летит на 20 % быстрее",
			"высшая ступень"],''','''			"ледышка летит на 20 % быстрее",
			"заморозка ещё на 1 с дольше"],'''),
('''			"волна летит на 30 % быстрее",
			"высшая ступень"],''','''			"волна летит на 30 % быстрее",
			"сбитое управление ещё на 1 с дольше"],'''),
])
patch('ЭКОНОМИКА.md',[
('''| 3 | этот вид выпадает из бокса в 1.5 раза чаще (вес в `Weapons.random_weapon`) |''',
'''| 3 | этот вид выпадает из бокса в 1.5 раза чаще (вес в `Weapons.random_weapon`; в магазине об этом не пишем, 09.09) плюс своё: мина — три мины в ряд, масло — пятно ×1.4, магнит — отдёргивает и останавливает, глушилка и заморозка — ещё +1 с, лазер — луч дольше, авиаудар — четыре ракеты, турбина — сильнее, щит — красный |'''),
])
