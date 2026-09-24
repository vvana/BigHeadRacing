extends Node3D
## Стенд 22.09: КРАСНЫЙ ЩИТ МАРИОНЕТКИ НА СЕРВЕРЕ СУДИТ КАСАНИЕ ПО КАРТИНЕ
## ВЛАДЕЛЬЦА. Жалоба: «красная сфера не уничтожила машину, которая долго
## была в контакте» (онлайн, игрок толкал бота перед собой). На сервере
## марионетка игрока отстаёт от его настоящего места на путь до сервера, а
## бот на его экране отстаёт на буфер + путь от сервера: бот, прижатый к
## бамперу НА ЭКРАНЕ, на сервере едет на (буфер + пинг) × скорость впереди
## марионетки — вне сферы. Теперь _shield_sweep марионетки отматывает
## соперников на это отставание, как выстрел (net_shot_lag / past_position).
## Сцена оффлайн, Net.mode переключается в SERVER после загрузки (rpc без
## пира ругается в журнал, но не мешает). Запуск:
## godot --headless --path . res://tools/TestShieldLag.tscn
## Вердикт — строка «SHIELD LAG TEST: PASS|FAIL».

const SPEED := 20.0
const CLIENT_LAG := 0.20   # буфер + путь сервер→клиент (net_client_lag)
const WIRE_LAG := 0.03     # путь клиент→сервер (net_wire_lag)
const CASE_LEN := 90

var _main: Node3D
var _frame := 0
var _ok := {}
var _holder: Car
var _bot: Car
var _base := Vector3.ZERO
var _tan := Vector3.FORWARD
var _cases: Array = []
var _ci := -1
var _case_start := 0
var _killed_at := -1
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
		_holder = cars[1]
		_bot = cars[2]
		var track: TrackBuilder = _main._track
		_base = track._curve.sample_baked(40.0)
		_tan = (track._curve.sample_baked(41.0) - _base).normalized()
		_tan.y = 0.0
		_tan = _tan.normalized()
		_place(_holder, _base, _tan)
		_holder.net_make_puppet()
		_holder.net_client_lag = CLIENT_LAG
		_holder.net_wire_lag = WIRE_LAG
		Net.mode = Net.Mode.SERVER
		# [имя, скорость, где бот НА ЭКРАНЕ владельца (вдоль курса, м от
		#  центра держателя), ждём ли уничтожения, держатель — бот?]
		# Зеркало (22.09): щит у БОТА, коснувшийся — марионетка игрока. На
		# его экране бот отстаёт на net_client_lag + net_wire_lag; ставим
		# бота на сервере туда, где он при данной картине игрока.
		_cases = [
			["стоя: бот в бампер сзади", 0.0, -3.2, true, false],
			["едут 20: игрок толкает бота перед собой", SPEED, 3.2, true, false],
			["едут 20: бот в 6 м позади на экране (на сервере — внутри)", SPEED, -6.0, false, false],
			["едут 20: бот в бампер сзади", SPEED, -3.2, true, false],
			["едут 20: бот в 8 м впереди на экране", SPEED, 8.0, false, false],
			["ЩИТ БОТА, едут 20: игрок упёрся в бота перед собой — погиб", SPEED, 3.2, true, true],
			["ЩИТ БОТА, едут 20: бот в 6 м позади на экране — жив", SPEED, -6.0, false, true],
		]
		return
	var lag_total := CLIENT_LAG + WIRE_LAG
	var t := _frame - _case_start
	if _ci < 0 or t >= CASE_LEN:
		if _ci >= 0:
			var c: Array = _cases[_ci]
			var expect: bool = c[3]
			var killed := _killed_at >= 0
			var victim: Car = _holder if bool(c[4]) else _bot
			_check(c[0], killed == expect, "уничтожен=%s на кадре %d, gap сейчас %.2f, level %d/%d" % [
					killed, _killed_at,
					_bot.global_position.distance_to(_holder.global_position),
					_holder.shield_level(), _bot.shield_level()])
		_ci += 1
		if _ci >= _cases.size():
			var all_ok := true
			for k in _ok:
				print("  %s  %s" % ["ok  " if _ok[k] else "FAIL", k])
				all_ok = all_ok and bool(_ok[k])
			print("SHIELD LAG TEST: %s" % ("PASS" if all_ok else "FAIL"))
			get_tree().quit(0 if all_ok else 1)
			return
		_case_start = _frame
		_killed_at = -1
		_t = 0.0
		var c: Array = _cases[_ci]
		var v: float = c[1]
		var bot_shield: bool = c[4]
		_place(_holder, _base, _tan)
		_holder._respawn_wait = 0.0
		_holder._ghost_time = 0.0
		_holder._shield_level = 3
		_holder._shield_time = 0.0 if bot_shield else 8.0
		_holder.net_apply_snapshot(_holder.global_position,
				_holder.global_transform.basis.get_rotation_quaternion(),
				_tan * v, 1.0)
		_place(_bot, _base + _tan * (float(c[2]) + lag_total * v), _tan)
		_bot._respawn_wait = 0.0
		_bot._ghost_time = 0.0
		_bot._shield_level = 3
		_bot._shield_time = 8.0 if bot_shield else 0.0
		# Серверная история бота — как будто он так и ехал последние 0.7 с
		# (в игре она всегда полна; пустая после телепорта — отдельный
		# случай, там отмотка просто даёт «далеко» и сфера молчит).
		_bot._pos_hist.clear()
		for k in range(44, -1, -1):
			_bot._pos_hist.push_back(_bot.global_position - _tan * v * (k / 60.0))
		_bot.linear_velocity = _tan * v
		return
	var c: Array = _cases[_ci]
	var v: float = c[1]
	_t += delta
	var victim: Car = _holder if bool(c[4]) else _bot
	if _killed_at < 0 and (victim.is_ghost() or victim._respawn_wait > 0.0):
		_killed_at = t
	# Снимок владельца: едет ровно, стемп растёт.
	_holder.net_apply_snapshot(_base + _tan * v * _t + Vector3.UP * 0.62,
			_holder.global_transform.basis.get_rotation_quaternion(),
			_tan * v, 1.0 + _t)
	# Бот на сервере: относительно НАСТОЯЩЕГО места игрока (снимка) он
	# впереди на lag × v против того, что видит владелец.
	if _killed_at < 0:
		_bot.global_position = _base + _tan * (v * _t + float(c[2]) + lag_total * v) \
				+ Vector3.UP * 0.62
		_bot.linear_velocity = _tan * v
		_bot.angular_velocity = Vector3.ZERO
