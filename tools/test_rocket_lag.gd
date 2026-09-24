extends Node3D
## Стенд 22.09: РАКЕТА БОТА СУДИТ ПОПАДАНИЕ В ЖИВОГО ИГРОКА ПО ЕГО ЭКРАНУ.
## Копия снаряда у игрока появляется по rpc на полпути позже, сам он на
## сервере — марионетка на полпути позади: на его экране ракета отстаёт от
## серверной на пинг (55 м/с × 0.2 с = 11 м). Раньше сервер бил по телу
## марионетки — «на экране ракета ещё летит, а взрыв уже есть».
## Сцена оффлайн, Net.mode = SERVER после загрузки. Жертва едет на 20 м/с
## по оси трассы снимками, бот сзади пускает ракету (летит прямо, 55 м/с).
## Запуск: godot --headless --path . res://tools/TestRocketLag.tscn
## Вердикт — строка «ROCKET LAG TEST: PASS|FAIL».

const SPEED := 20.0
const HALF_RTT := 0.10   # net_wire_lag жертвы: пинг 0.2 с
const CASE_LEN := 120

var _main: Node3D
var _frame := 0
var _ok := {}
var _victim: Car
var _bot: Car
var _base := Vector3.ZERO
var _tan := Vector3.FORWARD
var _off0 := 80.0
var _curve: Curve3D
var _cases: Array = []
var _ci := -1
var _case_start := 0
var _hit_at := -1
var _t := 0.0


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


func _check(name: String, cond: bool, note := "") -> void:
	_ok[name] = cond
	if not cond and note != "":
		print("  [%s] %s" % [name, note])


func _dir_at(off: float) -> Vector3:
	var d := _curve.sample_baked(off + 1.0) - _curve.sample_baked(off)
	d.y = 0.0
	return d.normalized()


func _physics_process(delta: float) -> void:
	_frame += 1
	var cars: Array = _main._cars
	if cars.size() < 4 or _frame < 30:
		return
	if _frame == 30:
		for c: Car in cars:
			c.controls_enabled = false
			c.alive = false
			c.ghost_time = 0.0
			c.global_position = Vector3(120.0, 2.0, 120.0 + 10.0 * cars.find(c))
		_victim = cars[1]
		_bot = cars[2]
		_curve = _main._track._curve
		# Самый прямой участок (ракета летит по прямой, жертва — по оси).
		var best := 1.0e9
		var length := _curve.get_baked_length()
		var o := 60.0
		while o < length - 60.0:
			var turn := 0.0
			var prev := _dir_at(o - 36.0)
			var q := o - 30.0
			while q <= o + 30.0:
				var d := _dir_at(q)
				turn += prev.angle_to(d)
				prev = d
				q += 6.0
			if turn < best:
				best = turn
				_off0 = o
			o += 5.0
		print("[стенд] прямой участок: отметка %.0f м, поворот на 60 м %.1f°" % [_off0, rad_to_deg(best)])
		_base = _curve.sample_baked(_off0)
		_tan = _dir_at(_off0)
		_place(_victim, _base, _tan)
		_victim.net_make_puppet()
		Net.mode = Net.Mode.SERVER
		# [имя, полпинга жертвы, дистанция бота позади (м), ждём гибели,
		#  ожидаемый кадр (−1 — не важен), срок ракеты (с)]
		# Сближение 55 − 20 = 35 м/с; ракета рождается у носа (+1.6 м), бьёт
		# за HIT_R 1.6 + пробу 1.1 до центра: путь короче на ~4.3 м. С пингом
		# 0.2 (отмотка 0.17 с) на экране ракета на 9.35 м позади серверной:
		# сервер бьёт на t = (D − 4.3) / 35, отмотанный отрезок касается на
		# t = (D + 5) / 35 и засчитывается, если его возраст t − 0.17 < срока.
		# D = 24, срок 0.6: сервер 0.56 с (< 0.6, без пинга бьёт), с пингом
		# касание на 0.83 с при возрасте 0.66 — копия уже погасла.
		_cases = [
			["без пинга: ракета с 20 м бьёт (~27 кадр)", 0.0, 20.0, true, 27, 2.2],
			["пинг 0.2: ракета с 20 м бьёт, когда ДОЛЕТЕЛА НА ЭКРАНЕ (~43 кадр)", HALF_RTT, 20.0, true, 43, 2.2],
			["пинг 0.2: ракета 0.6 с с 24 м на сервере достаёт (0.56 с), на экране гаснет раньше — НЕ бьёт", HALF_RTT, 24.0, false, -1, 0.6],
			["без пинга: ракета 0.6 с с 24 м бьёт (~34 кадр)", 0.0, 24.0, true, 34, 0.6],
		]
		return
	var t := _frame - _case_start
	if _ci < 0 or t >= CASE_LEN:
		if _ci >= 0:
			var c: Array = _cases[_ci]
			var expect: bool = c[3]
			var want_at: int = c[4]
			var hit := _hit_at >= 0
			var ok := hit == expect and (want_at < 0 or not hit or absi(_hit_at - want_at) <= 8)
			_check(c[0], ok, "погибла=%s на кадре %d (ждали %s, кадр %d)" % [
					hit, _hit_at, expect, want_at])
		_ci += 1
		if _ci >= _cases.size():
			var all_ok := true
			for k in _ok:
				print("  %s  %s" % ["ok  " if _ok[k] else "FAIL", k])
				all_ok = all_ok and bool(_ok[k])
			print("ROCKET LAG TEST: %s" % ("PASS" if all_ok else "FAIL"))
			get_tree().quit(0 if all_ok else 1)
			return
		_case_start = _frame
		_hit_at = -1
		_t = 0.0
		var c: Array = _cases[_ci]
		for n in _main.get_children():
			if n is Projectile:
				n.queue_free()
		_place(_victim, _base, _tan)
		_victim._respawn_wait = 0.0
		_victim._ghost_time = 0.0
		_victim._shield_time = 0.0
		_victim.net_wire_lag = c[1]
		_victim.net_apply_snapshot(_victim.global_position,
				_victim.global_transform.basis.get_rotation_quaternion(),
				_tan * SPEED, 1.0)
		var boff := _off0 - float(c[2])
		_place(_bot, _curve.sample_baked(boff), _tan)
		_bot.linear_velocity = _tan * SPEED
		var pr := Projectile.new()
		pr.shooter = _bot
		pr.direction = _tan
		pr.lag = 0.0
		pr.life_mult = float(c[5]) / 2.2
		_main.add_child(pr)
		pr.global_position = Car.muzzle_at(_bot.global_position, _tan)
		return
	_t += delta
	if _hit_at < 0 and (_victim.is_ghost() or _victim._respawn_wait > 0.0):
		_hit_at = t
	# Жертва — по прямой от старта (ракета летит прямо; участок прямой).
	_victim.net_apply_snapshot(_base + _tan * SPEED * _t + Vector3.UP * 0.62,
			Basis.looking_at(_tan).get_rotation_quaternion(), _tan * SPEED, 1.0 + _t)
	_bot.linear_velocity = _tan * SPEED
