extends Node3D
## Автотест «стрелял в бота прямо передо мной — оружие пролетело сквозь
## него» (жалоба 31.08, про ракету). Причина: снаряд летел ПО ПРЯМОЙ с
## высоты выстрела, а дорога — нет. На спуске полотно уходит вниз, снаряд
## проходил НАД крышей цели; на подъёме — втыкался в асфальт, не долетев.
## Теперь Projectile прижимается к полотну (_hug_ground) и обязан попадать
## в обе стороны горки. На старом коде обе фазы FAIL.

var _main: Node3D
var _frame := 0
var _ok := {}
var _attacker: Car
var _victim: Car
const DIST := 18.0


func _ready() -> void:
	seed(5)
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
			Vector3(140.0, 2.0, 140.0) + Vector3.RIGHT * randf_range(0, 20))
	car.linear_velocity = Vector3.ZERO


## Отметка с САМЫМ КРУТЫМ перепадом высоты на DIST метров вперёд:
## want_drop > 0 — ищем спуск, < 0 — подъём. Горка у классики одна,
## профиль читаем прямо с кривой — правки профиля стенд не сломают.
func _steepest(want_drop: bool) -> float:
	var curve: Curve3D = _main._track._curve
	var length := curve.get_baked_length()
	var best_off := 0.0
	var best := 0.0
	var off := 0.0
	while off < length:
		var drop: float = curve.sample_baked(off).y \
				- curve.sample_baked(fposmod(off + DIST, length)).y
		if not want_drop:
			drop = -drop
		if drop > best:
			best = drop
			best_off = off
		off += 2.0
	print("  [склон] перепад %.2f м на %.0f м (отметка %.0f)"
			% [best if want_drop else -best, DIST, best_off])
	return best_off


## Стрелок и жертва на оси в DIST метрах по кривой, ракета в упор.
func _shot_phase(off: float) -> void:
	var curve: Curve3D = _main._track._curve
	var length := curve.get_baked_length()
	var a := curve.sample_baked(off)
	var b := curve.sample_baked(fposmod(off + DIST, length))
	var vd := curve.sample_baked(fposmod(off + DIST + 1.0, length)) - b
	var ad := b - a
	ad.y = 0.0
	vd.y = 0.0
	_place(_attacker, a, ad.normalized())
	_place(_victim, b, vd.normalized())
	_attacker.weapon = Weapons.ROCKET
	_attacker.use_weapon()


func _physics_process(_d: float) -> void:
	_frame += 1
	match _frame:
		160:
			for c: Car in _main._cars:
				c.controls_enabled = false
				c.weapon = -1
			_attacker = _main._cars[0]
			_victim = _main._cars[1]
			for i in range(2, _main._cars.size()):
				_park(_main._cars[i])
			# Фаза СПУСК: дорога уходит вниз, снаряд обязан спуститься с ней.
			_shot_phase(_steepest(true))
		220:
			_ok["попал под горку"] = _victim.is_ghost()
			if not _victim.is_ghost():
				print("  [спуск] жертва цела, alive=%s" % _victim.alive)
			_victim._end_ghost()
			# Фаза ПОДЪЁМ: раньше снаряд втыкался в склон, не долетев.
			_shot_phase(_steepest(false))
		280:
			_ok["попал в горку"] = _victim.is_ghost()
			var all_ok := true
			for k: String in _ok:
				if not _ok[k]:
					all_ok = false
				print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
			print("SHOTSLOPE TEST: %s" % ("PASS" if all_ok else "FAIL"))
			get_tree().quit(0 if all_ok else 1)
