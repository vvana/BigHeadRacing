extends Node3D
## Стенд СТУПЕНЕЙ ОРУЖИЯ (магазин, 08.09): что меняет каждая ступень в
## бою. Оффлайн-заезд, атакующий — машина игрока (_cars[0]) с набором
## ступеней, который стенд подменяет по фазам (Car.weapon_steps), жертвы
## — обездвиженные боты. Запуск:
## godot --headless --path . res://tools/TestWeaponSteps.tscn
## Вердикт — строка «WEAPON STEPS TEST: PASS|FAIL».

var _main: Node3D
var _frame := 0
var _base := Vector3.ZERO
var _tan := Vector3.FORWARD
var _right := Vector3.RIGHT
var _ok := {}
var _wave_start := Vector3.ZERO
var _lead_expect := Vector3.ZERO


func _ready() -> void:
	seed(7)
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


## Набор ступеней с одним видом на ступени step (остальные — 0).
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


func _fire(attacker: Car, kind: int, step: int) -> void:
	attacker.weapon_steps = _steps(kind, step)
	attacker.weapon = kind
	attacker.use_weapon()


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame < 160:
		return
	var attacker: Car = _main._cars[0]
	var v1: Car = _main._cars[1]
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
			_place(attacker, _base, _tan)
			_park(v1)
			_park(v2)
			_park(v3)
			# МИНА: I ступень — одна мина, II — две.
			_fire(attacker, Weapons.MINE, 1)
			_ok["мина I: одна"] = _nodes(Mine).size() == 1
			_free_all(Mine)
			_fire(attacker, Weapons.MINE, 2)
			var mines := _nodes(Mine)
			_ok["мина II: две"] = mines.size() == 2
			if mines.size() == 2:
				var gap: float = (mines[0] as Node3D).global_position.distance_to(
						(mines[1] as Node3D).global_position)
				_ok["мина II: под разными колёсами"] = gap > 1.2 and gap < 2.0
			_free_all(Mine)
			# МАСЛО без II ступени: только замедляет.
			_fire(attacker, Weapons.OIL, 0)
		175:
			var slick: Node = _nodes(OilSlick)[0] if not _nodes(OilSlick).is_empty() else null
			_ok["масло 0: легло"] = slick != null
			if slick:
				_place(v1, (slick as Node3D).global_position, _tan)
				v1.linear_velocity = _tan * 10.0
		215:
			_ok["масло 0: только замедляет"] = v1.oil_slow_left() > 0.0 \
					and v1._slip_time <= 0.0
			if not _ok["масло 0: только замедляет"]:
				print("  [масло 0] slow=%.2f slip=%.2f" % [v1.oil_slow_left(), v1._slip_time])
			_free_all(OilSlick)
			_park(v1)
			# МАСЛО II: заносит, как раньше.
			_fire(attacker, Weapons.OIL, 2)
		230:
			var slick: Node = _nodes(OilSlick)[0] if not _nodes(OilSlick).is_empty() else null
			if slick:
				_place(v2, (slick as Node3D).global_position, _tan)
				v2.linear_velocity = _tan * 10.0
		270:
			_ok["масло II: заносит"] = v2._slip_time > 0.0
			_free_all(OilSlick)
			_park(v2)
			# ЛАЗЕР: без II ступени 120 м не достаёт, со II — достаёт.
			_place(attacker, _base, _tan)
			_place(v3, _base + _tan * 120.0, _tan)
			_fire(attacker, Weapons.LASER, 1)
		300:
			_ok["лазер I: 120 м не достаёт"] = not v3.is_ghost()
			_fire(attacker, Weapons.LASER, 2)
		330:
			_ok["лазер II: 120 м достаёт"] = v3.is_ghost()
			if v3.is_ghost():
				v3._end_ghost()
			_park(v3)
			# Луч жжёт всё время жизни (0.55 с) — гасим, иначе жертва
			# упреждения, поставленная на его линию, сгорит (поймано 08.09).
			attacker._laser_left = 0.0
			# АВИАУДАР: число ракет по ступени (I — 2, II — 3, III — 4).
			_fire(attacker, Weapons.AIRSTRIKE, 1)
			var a1 := _nodes(Airstrike)
			_ok["авиаудар I: 2 ракеты"] = a1.size() == 1 and a1[0]._spots.size() == 2
			_free_all(Airstrike)
			_fire(attacker, Weapons.AIRSTRIKE, 3)
			var a3 := _nodes(Airstrike)
			_ok["авиаудар III: 4 ракеты"] = a3.size() == 1 and a3[0]._spots.size() == 4
			_free_all(Airstrike)
			# Упреждение (II): жертва едет в 30 м впереди ПО ОСИ трассы со
			# скоростью 10 м/с — одна из теней должна лечь туда, где она
			# будет через секунду. По оси, а не по прямой от _base: тень
			# ложится на КОЛЕЮ жертвы (её боковое смещение от оси), и
			# ожидание, считанное по оси, расходилось бы на это смещение.
			var curve0: Curve3D = _main._track._curve
			var off30: float = curve0.get_baked_length() * 0.06 + 30.0
			var p30 := curve0.sample_baked(off30)
			var t30 := curve0.sample_baked(off30 + 1.0) - p30
			t30.y = 0.0
			t30 = t30.normalized()
			_place(v1, p30, t30)
			v1.linear_velocity = t30 * 10.0
		333:
			var curve: Curve3D = _main._track._curve
			var length := curve.get_baked_length()
			_lead_expect = curve.sample_baked(
					fposmod(v1.track_offset + 10.0 * Airstrike.SHADOW_DELAY + 1.5, length))
			_fire(attacker, Weapons.AIRSTRIKE, 2)
			var a2 := _nodes(Airstrike)
			var best := INF
			if a2.size() == 1:
				_ok["авиаудар II: 3 ракеты"] = a2[0]._spots.size() == 3
				for s: Vector3 in a2[0]._spots:
					best = minf(best, s.distance_to(_lead_expect))
			_ok["авиаудар II: упреждение по жертве"] = best < 4.0
			if best >= 4.0:
				print("  [авиаудар II] ближайшая тень к упреждению: %.1f м" % best)
				print("  [авиаудар II] ждали %s, жертва в %s (offset %.1f, alive=%s, ghost=%s, v=%.1f), тени: %s" % [
						_lead_expect, v1.global_position, v1.track_offset, v1.alive,
						v1.is_ghost(), v1.linear_velocity.length(),
						a2[0]._spots if a2.size() == 1 else "нет"])
				print("  [авиаудар II] прогресс атакующего %.1f, жертвы %.1f" % [
						_main.progress_of(attacker), _main.progress_of(v1)])
			_free_all(Airstrike)
			_park(v1)
			# БУСТ: длительность по ступени.
			_fire(attacker, Weapons.BOOST, 0)
			var b0: float = attacker._boost_time
			_fire(attacker, Weapons.BOOST, 2)
			var b2: float = attacker._boost_time
			# Ступень «0» у ускорения — это бесплатная I (Weapons.FREE_STEP,
			# 09.09): 1.15× против 1.5× у II.
			_ok["буст II дольше"] = b2 > b0 * 1.25 and b2 < b0 * 1.35
			# Волна перед носом (08.09): на II ступени её нет, на III — есть.
			attacker._tick_effects(0.016)
			_ok["буст II: волны перед носом нет"] = attacker._shock_fx != null \
					and not attacker._shock_fx.visible
			_fire(attacker, Weapons.BOOST, 3)
			attacker._tick_effects(0.016)
			_ok["буст III: волна перед носом"] = attacker._shock_fx != null \
					and attacker._shock_fx.visible
			attacker._boost_time = 0.0
			attacker._tick_effects(0.016)
			_ok["волна гаснет с бустом"] = not attacker._shock_fx.visible
			# МАГНИТ II: жертва впереди теряет всю скорость (её несёт назад).
			_place(v1, _base + _tan * 8.0, _tan)
			v1.linear_velocity = _tan * 14.0
			_fire(attacker, Weapons.MAGNET, 2)
		335:
			var along := v1.linear_velocity.dot(_tan)
			_ok["магнит II: скорость жертвы сброшена"] = along < 1.0
			if along >= 1.0:
				print("  [магнит II] скорость вдоль трассы %.1f" % along)
			_park(v1)
			# РАКЕТА: без II ступени снаряд проходит в 3 м от жертвы мимо,
			# со II — доворачивает и попадает.
			_place(attacker, _base, _tan)
			_place(v2, _base + _tan * 20.0 + _right * 3.0, _tan)
			_fire(attacker, Weapons.ROCKET, 1)
		400:
			_ok["ракета I: мимо в 3 м"] = not v2.is_ghost()
			_free_all(Projectile)
			_place(attacker, _base, _tan)
			_fire(attacker, Weapons.ROCKET, 2)
		470:
			_ok["ракета II: самонаведение"] = v2.is_ghost()
			if v2.is_ghost():
				v2._end_ghost()
			_park(v2)
			_free_all(Projectile)
			# ГЛУШИЛКА II: волна быстрее.
			_place(attacker, _base, _tan)
			_fire(attacker, Weapons.SCRAMBLE, 2)
			var w := _nodes(ScrambleWave)
			if not w.is_empty():
				_wave_start = (w[0] as Node3D).global_position
		480:
			var w := _nodes(ScrambleWave)
			var dist := -1.0
			if not w.is_empty():
				dist = (w[0] as Node3D).global_position.distance_to(_wave_start)
			# 10 кадров: обычная волна прошла бы ~8.3 м, быстрая — ~10.8.
			_ok["глушилка II быстрее"] = dist > 9.5
			if dist <= 9.5:
				print("  [глушилка II] за 10 кадров %.1f м" % dist)
			_free_all(ScrambleWave)
		500:
			var all_ok := true
			for k in _ok:
				print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
				all_ok = all_ok and _ok[k]
			print("WEAPON STEPS TEST: %s" % ("PASS" if all_ok else "FAIL"))
			get_tree().quit(0 if all_ok else 1)
