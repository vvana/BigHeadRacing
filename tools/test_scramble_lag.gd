extends Node3D
## Стенд 22.09: ВОЛНА ГЛУШИЛКИ БОТА СУДИТ ПОПАДАНИЕ В ЖИВОГО ИГРОКА ПО ЕГО
## ЭКРАНУ. Жалоба: «оглушение не зацепило меня, но сработало» (онлайн).
## Копия волны у игрока появляется по rpc на полпути позже, сам он на
## сервере — марионетка на полпути позади: на его экране волна отстаёт от
## серверной на пинг. Раньше сервер бил по текущему положению марионетки.
## Сцена оффлайн, Net.mode = SERVER после загрузки (rpc без пира ругается
## в журнал, не мешает). Жертва едет на 20 м/с снимками, бот сзади пускает
## волну (50 м/с, 1.8 с). Запуск:
## godot --headless --path . res://tools/TestScrambleLag.tscn
## Вердикт — строка «SCRAMBLE LAG TEST: PASS|FAIL».

const SPEED := 20.0
const HALF_RTT := 0.10   # net_wire_lag жертвы: пинг 0.2 с
const CASE_LEN := 170    # > 1.8 с жизни + 0.55 с дожития

var _main: Node3D
var _frame := 0
var _ok := {}
var _victim: Car
var _bot: Car
var _base := Vector3.ZERO
var _tan := Vector3.FORWARD
var _off0 := 80.0   # с запасом: бот стоит до 54 м позади, отметки не уходят в минус
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
		var track: TrackBuilder = _main._track
		_curve = track._curve
		# Самый прямой участок: волна катится по трассе с мягким доворотом,
		# а жертва здесь идёт строго по оси — на дуге они разошлись бы.
		var best := 1.0e9
		var length := _curve.get_baked_length()
		var o := 60.0
		while o < length - 60.0:
			var turn := 0.0
			var prev := _dir_at(o - 56.0)
			var q := o - 50.0
			while q <= o + 50.0:
				var d := _dir_at(q)
				turn += prev.angle_to(d)
				prev = d
				q += 6.0
			if turn < best:
				best = turn
				_off0 = o
			o += 5.0
		print("[стенд] прямой участок: отметка %.0f м, поворот на 100 м %.1f°" % [_off0, rad_to_deg(best)])
		_base = _curve.sample_baked(_off0)
		_tan = _dir_at(_off0)
		_place(_victim, _base, _tan)
		_victim.net_make_puppet()
		Net.mode = Net.Mode.SERVER
		# [имя, полпинга жертвы, дистанция бота позади (м), ждём оглушения,
		#  ожидаемый кадр оглушения (−1 — не важен), срок волны (с)]
		# Дальние случаи — с укороченным сроком волны 0.9 с (45 м пути):
		# прямых по 100 м на оси трассы нет, на дуге волна и жертва по оси
		# расходятся, а нам важен только момент «погасла до касания».
		# Арифметика: сервер бьёт на t = (D − 6.3) / 30; отмотанный отрезок
		# касается на t = (D + 2.2) / 30 и засчитывается, если его возраст
		# t − 0.17 < срока. При D = 31.5: сервер 0.84 с (< 0.9, без пинга
		# глушит), с пингом касание на 1.12 с при возрасте 0.95 — погасла.
		# Сближение 50 − 20 = 30 м/с; волна рождается у носа бота (+1.6 м) и
		# бьёт за HIT_R + запас + полкузова (~3 + 1.7 м) до центра: путь
		# короче дистанции на ~6.3 м. С пингом 0.2 (отмотка 0.17 с) на
		# экране жертвы волна на 8.3 м позади серверной — доходит на 0.28 с
		# (17 кадров) позже. Срок волны 1.8 с = 108 кадров.
		_cases = [
			["без пинга: волна с 20 м глушит (~28 кадр)", 0.0, 20.0, true, 28, 1.8],
			["пинг 0.2: волна с 20 м глушит, когда ДОШЛА НА ЭКРАНЕ (~45 кадр)", HALF_RTT, 20.0, true, 45, 1.8],
			["пинг 0.2: волна 0.9 с с 31.5 м на сервере достаёт (0.84 с), на экране гаснет раньше — НЕ глушит", HALF_RTT, 31.5, false, -1, 0.9],
			["без пинга: волна 0.9 с с 31.5 м глушит (~50 кадр)", 0.0, 31.5, true, 50, 0.9],
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
			_check(c[0], ok, "оглушён=%s на кадре %d (ждали %s, кадр %d)" % [
					hit, _hit_at, expect, want_at])
		_ci += 1
		if _ci >= _cases.size():
			var all_ok := true
			for k in _ok:
				print("  %s  %s" % ["ok  " if _ok[k] else "FAIL", k])
				all_ok = all_ok and bool(_ok[k])
			print("SCRAMBLE LAG TEST: %s" % ("PASS" if all_ok else "FAIL"))
			get_tree().quit(0 if all_ok else 1)
			return
		_case_start = _frame
		_hit_at = -1
		_t = 0.0
		var c: Array = _cases[_ci]
		for n in _main.get_children():
			if n is ScrambleWave:
				n.queue_free()
		_place(_victim, _base, _tan)
		_victim._scramble_time = 0.0
		_victim._shield_time = 0.0
		_victim.net_wire_lag = c[1]
		_victim.net_apply_snapshot(_victim.global_position,
				_victim.global_transform.basis.get_rotation_quaternion(),
				_tan * SPEED, 1.0)
		var boff := _off0 - float(c[2])
		var bdir := _dir_at(boff)
		_place(_bot, _curve.sample_baked(boff), bdir)
		_bot.linear_velocity = bdir * SPEED
		var w := ScrambleWave.new()
		w.shooter = _bot
		w.direction = bdir
		w.track = _main._track
		w.lag = 0.0
		w._life = float(c[5])
		_main.add_child(w)
		w.global_position = Car.muzzle_at(_bot.global_position, bdir)
		return
	_t += delta
	if OS.get_cmdline_user_args().has("--dbg") and t % 10 == 0:
		var wv: ScrambleWave = null
		for n in _main.get_children():
			if n is ScrambleWave:
				wv = n
		if wv != null:
			var d := wv.global_position - _victim.global_position
			print("[dbg] t=%d волна→жертва: вдоль %.1f поперёк %.1f dy %.2f | бот→жертва %.1f | dead=%s life=%.2f | касат %s" % [
					t, d.dot(_victim.true_forward()), Vector3(-_victim.true_forward().z, 0, _victim.true_forward().x).dot(d),
					d.y, (_bot.global_position - _victim.global_position).length(), wv._dead, wv._life,
					_dir_at(_off0 + SPEED * _t)])
	if _hit_at < 0 and _victim.scramble_left() > 0.0:
		_hit_at = t
	# Жертва едет ПО ОСИ ТРАССЫ (волна катится по ней же).
	var off := _off0 + SPEED * _t
	var dir := _dir_at(off)
	_victim.net_apply_snapshot(_curve.sample_baked(off) + Vector3.UP * 0.62,
			Basis.looking_at(dir).get_rotation_quaternion(), dir * SPEED, 1.0 + _t)
	var cc: Array = _cases[_ci]
	_bot.linear_velocity = _dir_at(_off0 - float(cc[2]) + SPEED * _t) * SPEED


func _dir_at(off: float) -> Vector3:
	var d := _curve.sample_baked(off + 1.0) - _curve.sample_baked(off)
	d.y = 0.0
	return d.normalized()
