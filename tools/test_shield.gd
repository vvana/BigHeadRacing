extends Node3D
## Стенд бонуса ЩИТ (Weapons.SHIELD, 08.09): длительность по ступени,
## защита от чужого оружия (ракета, ледышка, лазер, волна глушилки, мина,
## масло, магнит), жёлтый щит II замедляет коснувшегося, красный III —
## уничтожает, щит о щит — ничего; байт снимка для сети. Оффлайн-заезд,
## как в TestWeaponSteps: атакующий — машина игрока (_cars[0]), держатель
## щита и жертвы — обездвиженные боты. Запуск:
## godot --headless --path . res://tools/TestShield.tscn
## Вердикт — строка «SHIELD TEST: PASS|FAIL».

var _main: Node3D
var _frame := 0
var _base := Vector3.ZERO
var _tan := Vector3.FORWARD
var _right := Vector3.RIGHT
var _ok := {}


func _ready() -> void:
	seed(11)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _place(car: Car, pos: Vector3, look: Vector3) -> void:
	car.alive = true
	car.global_transform = Transform3D(
			Basis.looking_at(look), pos + Vector3.UP * 0.62)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_speed_memory()
	car.reset_track_offset()


func _park(car: Car) -> void:
	car.alive = false
	car.global_transform = Transform3D(Basis.IDENTITY,
			Vector3(110.0, 2.0, 110.0) + Vector3.RIGHT * randf_range(0, 20))
	car.linear_velocity = Vector3.ZERO


func _steps(kind: int, step: int) -> PackedByteArray:
	var s := PackedByteArray()
	s.resize(Weapons.COUNT)
	s[kind] = step
	return s


func _nodes(type: Variant) -> Array:
	var out: Array = []
	for child in _main.get_children():
		if is_instance_of(child, type):
			out.append(child)
	return out


func _free_all(type: Variant) -> void:
	for n in _nodes(type):
		_main.remove_child(n)
		n.queue_free()


func _fire(car: Car, kind: int, step: int) -> void:
	car.weapon_steps = _steps(kind, step)
	car.weapon = kind
	car.use_weapon()


## Держатель заново под щитом заданной ступени, стоит в pos носом по трассе.
func _shield_up(car: Car, pos: Vector3, step: int) -> void:
	_place(car, pos, _tan)
	car._shield_time = 0.0
	_fire(car, Weapons.SHIELD, step)


func _check(name: String, cond: bool, note := "") -> void:
	_ok[name] = cond
	if not cond and note != "":
		print("  [%s] %s" % [name, note])


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame < 160:
		return
	var attacker: Car = _main._cars[0]
	var holder: Car = _main._cars[1]
	var v2: Car = _main._cars[2]
	var v3: Car = _main._cars[3]
	match _frame:
		160:
			var curve: Curve3D = _main._track._curve
			var off: float = curve.get_baked_length() * 0.06
			_base = curve.sample_baked(off)
			_tan = curve.sample_baked(off + 1.0) - _base
			_tan.y = 0.0
			_tan = _tan.normalized()
			_right = _tan.cross(Vector3.UP).normalized()
			for c: Car in _main._cars:
				c.controls_enabled = false
				c.weapon = -1
			for i in range(4, _main._cars.size()):
				_park(_main._cars[i])
			_park(v2)
			_park(v3)
			_place(attacker, _base, _tan)
			# ДЛИТЕЛЬНОСТЬ: «без ступени» — это бесплатная I (Weapons.FREE_STEP,
			# 09.09), 5 с + 15 %; уровень 1 и с 0, и с I; II → 2, III → 3.
			_shield_up(holder, _base + _tan * 15.0, 0)
			_check("щит 0 (= бесплатная I): 5.75 с", absf(holder.shield_left() - 5.75) < 0.05,
					"осталось %.2f" % holder.shield_left())
			_check("щит 0: уровень 1", holder.shield_level() == 1)
			_check("щит: значок над машиной",
					holder.status_icon_kind() == Weapons.SHIELD)
			_check("щит: сфера видна", holder._shield_mesh != null
					and holder._shield_mesh.visible)
			_shield_up(holder, _base + _tan * 15.0, 1)
			_check("щит I: 5.75 с", absf(holder.shield_left() - 5.75) < 0.05,
					"осталось %.2f" % holder.shield_left())
			_check("щит I: уровень 1", holder.shield_level() == 1)
			_shield_up(holder, _base + _tan * 15.0, 2)
			_check("щит II: уровень 2, 5.75 с", holder.shield_level() == 2
					and absf(holder.shield_left() - 5.75) < 0.05)
			_shield_up(holder, _base + _tan * 15.0, 3)
			_check("щит III: уровень 3", holder.shield_level() == 3)
			# Байт снимка: уровень и остаток доезжают до марионетки.
			holder._shield_time = 4.32
			var b := holder.shield_byte()
			v2.net_set_shield(b)
			_check("снимок: уровень и остаток",
					v2._shield_level == 3 and absf(v2._shield_time - 4.4) < 0.01,
					"байт %d → уровень %d, %.2f с" % [b, v2._shield_level, v2._shield_time])
			v2.net_set_shield(0)
			_check("снимок: ноль — щита нет", not v2.is_shielded())
			_park(v2)
			# РАКЕТА в защищённого с 15 м.
			_shield_up(holder, _base + _tan * 15.0, 0)
			_fire(attacker, Weapons.ROCKET, 0)
		205:
			_check("ракета: держатель цел", holder.alive and not holder.is_ghost())
			_check("ракета: погасла о щит", _nodes(Projectile).is_empty(),
					"снарядов %d" % _nodes(Projectile).size())
			_free_all(Projectile)
			# ЛЕДЫШКА.
			_place(attacker, _base, _tan)
			_fire(attacker, Weapons.FREEZE, 0)
		250:
			_check("ледышка: не заморозил", holder.freeze_left() <= 0.0,
					"лёд %.2f" % holder.freeze_left())
			_free_all(Projectile)
			# ЛАЗЕР.
			_place(attacker, _base, _tan)
			_fire(attacker, Weapons.LASER, 0)
		262:
			_check("лазер: держатель цел", holder.alive and not holder.is_ghost())
			attacker._laser_left = 0.0
			# ГЛУШИЛКА.
			_place(attacker, _base, _tan)
			_fire(attacker, Weapons.SCRAMBLE, 0)
		310:
			_check("глушилка: управление цело", holder.scramble_left() <= 0.0,
					"глушилка %.2f" % holder.scramble_left())
			_check("глушилка: волна погасла о щит", _nodes(ScrambleWave).is_empty())
			_free_all(ScrambleWave)
			# МАГНИТ II (обнуляет скорость незащищённым): держатель едет
			# 14 м/с в 8 м впереди — скорость должна остаться.
			_shield_up(holder, _base + _tan * 8.0, 0)
			holder.linear_velocity = _tan * 14.0
			_fire(attacker, Weapons.MAGNET, 2)
		312:
			var along := holder.linear_velocity.dot(_tan)
			_check("магнит: не тянет и не осаживает", along > 11.0,
					"скорость вдоль трассы %.1f" % along)
			# МИНА: держатель наезжает — мина рвётся, машина цела.
			_place(attacker, _base + _tan * 6.0, _tan)
			_fire(attacker, Weapons.MINE, 0)
		330:
			var mines := _nodes(Mine)
			_check("мина: легла", mines.size() == 1)
			if mines.size() == 1:
				var mp: Vector3 = (mines[0] as Node3D).global_position
				_shield_up(holder, mp - _tan * 2.0, 0)
				holder.linear_velocity = _tan * 8.0
			_place(attacker, _base + _tan * 40.0, _tan)
		380:
			_check("мина: рванула", _nodes(Mine).is_empty(),
					"мин на трассе %d" % _nodes(Mine).size())
			_check("мина: держатель цел и не отброшен",
					holder.alive and not holder.is_ghost()
					and holder.linear_velocity.length() < 12.0,
					"alive=%s ghost=%s v=%.1f" % [holder.alive, holder.is_ghost(),
					holder.linear_velocity.length()])
			_free_all(Mine)
			# МАСЛО II (занос): под щитом ни заноса, ни замедления.
			_place(attacker, _base + _tan * 6.0, _tan)
			_fire(attacker, Weapons.OIL, 2)
		395:
			var slicks := _nodes(OilSlick)
			_check("масло: легло", slicks.size() == 1)
			if slicks.size() == 1:
				_shield_up(holder, (slicks[0] as Node3D).global_position, 0)
				holder.linear_velocity = _tan * 10.0
			_place(attacker, _base + _tan * 40.0, _tan)
		435:
			_check("масло: ни заноса, ни замедления",
					holder._slip_time <= 0.0 and holder.oil_slow_left() <= 0.0,
					"slip %.2f slow %.2f" % [holder._slip_time, holder.oil_slow_left()])
			_free_all(OilSlick)
			_place(attacker, _base + _tan * 60.0, _tan)
			# ЩИТ II: v2 таранит держателя — теряет скорость, но жив.
			_place(holder, _base, _tan)
			holder._shield_time = 0.0
			_fire(holder, Weapons.SHIELD, 2)
			_place(v2, _base + _tan * 5.0, -_tan)
			v2.linear_velocity = -_tan * 9.0
		490:
			_check("щит II: коснувшийся замедлен", v2.oil_slow_left() > 0.0
					or v2.status_icon_kind() == Weapons.SHIELD,
					"slow %.2f, v %.1f, gap %.1f" % [v2.oil_slow_left(),
					v2.linear_velocity.length(),
					v2.global_position.distance_to(holder.global_position)])
			_check("щит II: коснувшийся жив", v2.alive and not v2.is_ghost())
			_check("щит II: держатель жив", holder.alive and not holder.is_ghost())
			_park(v2)
			# ЩИТ III: v3 таранит — уничтожен, держатель цел.
			_place(holder, _base, _tan)
			holder._shield_time = 0.0
			_fire(holder, Weapons.SHIELD, 3)
			_place(v3, _base + _tan * 5.0, -_tan)
			v3.linear_velocity = -_tan * 9.0
		545:
			_check("щит III: коснувшийся уничтожен", v3.is_ghost(),
					"gap %.1f alive=%s" % [v3.global_position.distance_to(
					holder.global_position), v3.alive])
			_check("щит III: держатель цел", holder.alive and not holder.is_ghost())
			_park(v3)
			# ЩИТ о ЩИТ: оба красные — никто не гибнет.
			_place(holder, _base, _tan)
			holder._shield_time = 0.0
			_fire(holder, Weapons.SHIELD, 3)
			_place(attacker, _base + _tan * 5.0, -_tan)
			attacker._shield_time = 0.0
			_fire(attacker, Weapons.SHIELD, 3)
			attacker.linear_velocity = -_tan * 9.0
		600:
			_check("щит о щит: оба целы", holder.alive and not holder.is_ghost()
					and attacker.alive and not attacker.is_ghost()
					and attacker.oil_slow_left() <= 0.0)
			# ИСТЕЧЕНИЕ: остаток 0.2 с — через 20 кадров щита нет, сфера скрыта.
			holder._shield_time = 0.2
			attacker._shield_time = 0.0
			_place(attacker, _base + _tan * 60.0, _tan)
		625:
			_check("щит истёк", not holder.is_shielded()
					and holder.status_icon_kind() != Weapons.SHIELD
					and holder._shield_mesh != null and not holder._shield_mesh.visible)
			# И без щита ракета снова убивает (защита не «прилипла»).
			_place(attacker, _base, _tan)
			_place(holder, _base + _tan * 15.0, _tan)
			_fire(attacker, Weapons.ROCKET, 0)
		670:
			_check("без щита: ракета убивает", holder.is_ghost())
			_free_all(Projectile)
		690:
			var all_ok := true
			for k in _ok:
				print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
				all_ok = all_ok and _ok[k]
			print("SHIELD TEST: %s" % ("PASS" if all_ok else "FAIL"))
			get_tree().quit(0 if all_ok else 1)
