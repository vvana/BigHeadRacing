extends Node3D
## Функциональный тест системы оружия: сценарные фазы по кадрам.
## Атакующий — машина игрока (_cars[0]), жертвы — ИИ (обездвижены).

var _main: Node3D
var _frame := 0
var _base := Vector3.ZERO
var _tan := Vector3.FORWARD
var _right := Vector3.RIGHT
var _ok := {}
var _wall_n := Vector3.RIGHT
var _beam_pos := Vector3.ZERO   # где был луч лазера до сдвига машины


func _ready() -> void:
	seed(42)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _place(car: Car, pos: Vector3, look: Vector3) -> void:
	car.alive = true  # запаркованные за картой стоят с alive=false
	car.global_transform = Transform3D(
			Basis.looking_at(look), pos + Vector3.UP * 0.62)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_speed_memory()


## Парковка за картой: alive=false, чтобы автовозврат Main._check_recovery
## не вернул машину на трассу (прямо под пролетающие снаряды теста).
func _park(car: Car) -> void:
	car.alive = false
	car.global_transform = Transform3D(Basis.IDENTITY,
			Vector3(110.0, 2.0, 110.0) + Vector3.RIGHT * randf_range(0, 20))
	car.linear_velocity = Vector3.ZERO


func _find_node(type: Variant) -> Node:
	for child in _main.get_children():
		if is_instance_of(child, type):
			return child
	return null


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
			# Отсчёт кончился (все controls_enabled=true) — глушим всех.
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
			# Заезд теперь бывает и на 8 машин (размер выбирается в гараже и
			# лежит в профиле). Стенд работает с четырьмя — ЛИШНИЕ убираем за
			# карту, иначе они болтаются на трассе, ловят чужие снаряды и
			# толкают жертв: «мина толкает дальних» падала именно из-за них.
			for i in range(4, _main._cars.size()):
				_park(_main._cars[i])
			# Фаза РАКЕТА: жертва в 15 м строго впереди.
			_place(attacker, _base, _tan)
			_place(v1, _base + _tan * 15.0, _tan)
			_park(v2)
			_park(v3)
			attacker.weapon = Weapons.ROCKET
			attacker.use_weapon()
		220:
			_ok["ракета"] = v1.is_ghost()
			# Фаза ЛЁД: жертва 2 впереди, стреляем ледышкой.
			_place(v2, _base + _tan * 15.0, _tan)
			attacker.weapon = Weapons.FREEZE
			attacker.use_weapon()
		290:
			_ok["лёд"] = v2._freeze_time > 0.5
			# Заражение: жертва 3 вплотную к замороженной (внахлёст бортами).
			_place(v3, v2.global_position + _right * 1.6 - Vector3.UP * 0.62,
					_tan)
		350:
			_ok["лёд заразен"] = v3._freeze_time > 0.0
			_park(v2)
			_park(v3)
			# Фаза МИНА: кладём, ставим жертву 1 на неё до взведения —
			# наехавшего мина с 31.08 УНИЧТОЖАЕТ. Жертву 3 ставим в 6.5 м
			# сбоку: дальше смертельного радиуса (4 м), но в радиусе
			# взрыва (10 м) — её должно только оттолкнуть.
			# Жертва — НА ОСИ (по кривой, не по прямой: прямая на 25 м
			# уводит на ~5 м вбок, к стене).
			attacker.weapon = Weapons.MINE
			attacker.use_weapon()
			var mine: Node = _find_node(Mine)
			if mine:
				var curve: Curve3D = _main._track._curve
				var off: float = curve.get_baked_length() * 0.06
				var mp := curve.sample_baked(off + 25.0)
				var md := curve.sample_baked(off + 26.0) - mp
				md.y = 0.0
				_place(v1, mp, md.normalized())
				(mine as Node3D).global_position = \
						v1.global_position - Vector3.UP * 0.4
				_place(v3, mp + _right * 6.5, md.normalized())
		420:
			_ok["мина уничтожает наехавшего"] = v1.is_ghost()
			_ok["мина толкает дальних"] = v3.linear_velocity.length() > 2.0 \
					and not v3.is_ghost()
			# Призрака с жертвы снимаем вручную: дальше она нужна живой
			# (магнит и масло призрака не берут — у него снят слой машин).
			v1._end_ghost()
			# Фаза ЛАЗЕР: две жертвы на одной линии.
			# ВАЖНО: жертву мины сначала убираем с линии огня. Она стоит
			# в 25 м по КРИВОЙ, и на трассе с прямыми участками это может
			# совпасть с лучом (70 м по прямой) — тогда она уезжает в
			# призраки, а следующие фазы (магнит, масло) призрака не берут:
			# у него снят слой машин, Area3D пятна и магнит его не видят.
			_park(v1)
			_place(v2, _base + _tan * 12.0, _tan)
			_place(v3, _base + _tan * 24.0, _tan)
			_place(attacker, _base, _tan)
			attacker.weapon = Weapons.LASER
			attacker.use_weapon()
		440:
			_ok["лазер x2"] = v2.is_ghost() and v3.is_ghost()
			# Фаза БУСТ.
			attacker.weapon = Weapons.BOOST
			attacker.use_weapon()
			_ok["буст"] = attacker._boost_time > 1.0
			# Фаза МАГНИТ: жертва 1 в 8 м впереди, стоит.
			_place(v1, _base + _tan * 8.0, _tan)
		460:
			attacker.weapon = Weapons.MAGNET
			attacker.use_weapon()
		470:
			var to_attacker: Vector3 = \
					(attacker.global_position - v1.global_position).normalized()
			var pull := v1.linear_velocity.dot(to_attacker)
			_ok["магнит"] = pull > 1.0
			# Значки действующих эффектов над крышей: жертве магнита —
			# магнит, атакующему (буст ещё идёт с фазы выше) — ускорение.
			_ok["значок магнита у жертвы"] = 					v1._status_icon.visible and v1._status_shown == Weapons.MAGNET
			_ok["значок буста у атакующего"] = 					attacker._status_icon.visible 					and attacker._status_shown == Weapons.BOOST
			if pull <= 1.0:
				print("  [магнит] тяга %.2f м/с, жертва в %.1f м от оси, " % [
					pull, _main._track.distance_from_axis(v1.global_position)],
					"призрак=", v1.is_ghost(), " alive=", v1.alive)
			# Фаза МАСЛО.
			attacker.weapon = Weapons.OIL
			attacker.use_weapon()
		490:
			var slick: Node = _find_node(OilSlick)
			_ok["масло легло"] = slick != null
			if slick:
				_place(v1, (slick as Node3D).global_position, _tan)
				v1.linear_velocity = _tan * 10.0
		530:
			_ok["масло заносит"] = v1._slip_time > 0.0
			if v1._slip_time <= 0.0:
				var slick2: Node = _find_node(OilSlick)
				print("  [масло] жертва в %.1f м от оси, скорость %.1f, " % [
					_main._track.distance_from_axis(v1.global_position),
					v1.linear_velocity.length()],
					"пятно живо=", slick2 != null)
			# Фаза МАСЛО У СТЕНЫ: занос обязан крутить нос ОТ ограждения.
			# Ставим жертву вплотную к внешнему борту, носом строго вдоль
			# трассы, и роняем на неё занос напрямую (пятно тут не нужно —
			# проверяем ВЫБОР СТОРОНЫ, а не срабатывание Area3D).
			_park(v2)
			_park(v3)
			var hw: float = _main._track.half_width_at_pos(_base) 					- TrackBuilder.WALL_THICKNESS * 0.5
			_place(v1, _base + _right * (hw - 1.0), _tan)
			v1.linear_velocity = _tan * 8.0
			v1._slip_time = 0.0
			v1.apply_oil_slip()
			_wall_n = _right
			_ok["занос у стены не в стену"] = 					signf(v1.angular_velocity.y) 					== -signf((-v1.global_transform.basis.z).signed_angle_to(
							_wall_n, Vector3.UP))
		560:
			# И через полсекунды нос действительно ушёл ОТ стены.
			var fwd_now := -v1.global_transform.basis.z
			fwd_now.y = 0.0
			var into := fwd_now.normalized().dot(_wall_n)
			_ok["нос ушёл от стены"] = into < -0.15
			if into >= -0.15:
				print("  [масло у стены] проекция носа на стену %.2f" % into)
			# Фаза АВИАУДАР.
			_place(attacker, _base, _tan)
			attacker.weapon = Weapons.AIRSTRIKE
			attacker.use_weapon()
			_ok["авиаудар создан"] = _find_node(Airstrike) != null
		600:
			# Фаза ЛУЧ ЕДЕТ С МАШИНОЙ: стержень лазера привязан к носу
			# стрелявшего (31.08: «лазер остаётся на том месте, где
			# применили»). Прошлый луч (фаза 420) к этому кадру уже погас —
			# LIFETIME 0.55 c, иначе _find_node вернул бы его.
			_place(attacker, _base, _tan)
			attacker.weapon = Weapons.LASER
			attacker.use_weapon()
		601:
			var beam := _find_node(LaserFx) as Node3D
			_ok["луч нарисован"] = beam != null
			if beam:
				_beam_pos = beam.global_position
				attacker.global_position += _tan * 10.0
		602:
			var beam2 := _find_node(LaserFx) as Node3D
			_ok["луч едет с машиной"] = beam2 != null \
					and (beam2.global_position - _beam_pos).dot(_tan) > 8.0
			if beam2:
				print("  [луч] сдвинулся на %.1f м вслед за машиной"
						% (beam2.global_position - _beam_pos).dot(_tan))
		610:
			# Фаза ГЛУШИЛКА: звуковая волна по жертве в 15 м впереди.
			_place(attacker, _base, _tan)
			_place(v2, _base + _tan * 15.0, _tan)
			attacker.weapon = Weapons.SCRAMBLE
			attacker.use_weapon()
		640:
			_ok["авиаудар отработал"] = _find_node(Airstrike) == null
			# Волна летит 15 м на 38 м/с — к этому кадру уже долетела.
			_ok["глушилка сбила управление"] = v2.scramble_left() > 4.0
			# Фаза БОКС: пустые руки + бокс на пути.
			attacker.weapon = -1
			var box := WeaponBox.new()
			add_child(box)
			box.global_position = _base + _tan * 5.0 + Vector3.UP * 0.85
			_place(attacker, _base + _tan * 4.0, _tan)
		700:
			_ok["бокс дал оружие"] = attacker.weapon >= 0
			var all_ok := true
			for k: String in _ok:
				if not _ok[k]:
					all_ok = false
				print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
			print("WEAPONS TEST: %s" % ("PASS" if all_ok else "FAIL"))
			get_tree().quit(0 if all_ok else 1)
