extends Node3D
## Стенд 22.09: ТАРАН ЖИВОГО ИГРОКА ПО БОТУ доходит до бота (жалоба «при
## столкновении с машиной противника ничего не происходит, противник едет
## как по рельсам»). Сцена оффлайн, Net.mode = SERVER: машина 1 —
## марионетка живого игрока (агрессор), машина 2 — бот. Клиентский доклад
## о таране (_rx_shove) проверяем через Main._apply_shove_report:
##   1) бот в 3 м впереди — толчок принят: скорость вдоль dir и закрутка;
##   2) повторный доклад через кадр — отброшен (не чаще 0.15 с);
##   3) бот в 15 м (и в истории тоже) — доклад отброшен, бот стоит;
##   4) дедуп: бот сам уже отработал контакт с этой марионеткой
##      (_touch_mute свежий) — событие принято, но толчка нет.
## Запуск: godot --headless --path . res://tools/TestBotShove.tscn
## Вердикт — строка «BOT SHOVE TEST: PASS|FAIL».

var _main: Node3D
var _frame := 0
var _ok := {}
var _attacker: Car
var _bot: Car
var _dir := Vector3.ZERO


func _ready() -> void:
	process_physics_priority = 100
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _check(name: String, cond: bool, note := "") -> void:
	_ok[name] = cond
	print("  %s  %s%s" % ["ok  " if cond else "FAIL", name,
			("" if cond or note == "" else " — " + note)])


func _put_bot(ahead: float) -> void:
	var fwd: Vector3 = -_attacker.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	_bot.global_transform = Transform3D(_attacker.global_transform.basis,
			_attacker.global_position + fwd * ahead)
	_bot.linear_velocity = Vector3.ZERO
	_bot.angular_velocity = Vector3.ZERO
	_bot.reset_speed_memory()
	_dir = fwd


func _physics_process(_d: float) -> void:
	_frame += 1
	var cars: Array = _main._cars
	if cars.size() < 3 or _frame < 30:
		return
	if _frame == 30:
		for i in cars.size():
			var c: Car = cars[i]
			c.controls_enabled = false
			if i != 1 and i != 2:
				c.alive = false
				c.global_position = Vector3(150, 2, 150 + i * 8)
		_attacker = cars[1]
		_bot = cars[2]
		_attacker.alive = true
		_bot.alive = true
		_attacker.linear_velocity = Vector3.ZERO
		_attacker.net_make_puppet()
		Net.mode = Net.Mode.SERVER
		_put_bot(3.0)
		return
	if _frame == 40:
		_bot.linear_velocity = Vector3.ZERO
		var took: bool = _main._apply_shove_report(1, 2, _dir, 10.0, 1.5)
		_check("доклад по боту в 3 м принят", took)
		return
	if _frame == 41:
		var v: float = _bot.linear_velocity.dot(_dir)
		_check("бот получил толчок и закрутку",
				v > 2.5 and absf(_bot.angular_velocity.y) > 0.4,
				"v=%.1f м/с, закрутка %.2f" % [v, _bot.angular_velocity.y])
		var again: bool = _main._apply_shove_report(1, 2, _dir, 10.0, 1.5)
		_check("повтор через кадр отброшен", not again)
		return
	if _frame == 60:
		_put_bot(15.0)
		return
	if _frame == 80:
		# 20 кадров: история позиций бота (0.12 с отмотки) уже далеко.
		var took: bool = _main._apply_shove_report(1, 2, _dir, 10.0, 1.5)
		_check("доклад по боту в 15 м отброшен", not took)
		return
	if _frame == 81:
		_check("бот в 15 м не сдвинулся",
				_bot.linear_velocity.length() < 0.8,
				"v=%.1f" % _bot.linear_velocity.length())
		_put_bot(3.0)
		return
	if _frame == 100:
		_bot.linear_velocity = Vector3.ZERO
		_bot._touch_mute[_attacker.get_instance_id()] = \
				float(Time.get_ticks_msec())
		_main._apply_shove_report(1, 2, _dir, 10.0, 1.5)
		return
	if _frame == 101:
		_check("дубль после рикошета бота отброшен",
				_bot.linear_velocity.length() < 0.8,
				"v=%.1f" % _bot.linear_velocity.length())
		var all_ok := true
		for k in _ok:
			all_ok = all_ok and bool(_ok[k])
		print("BOT SHOVE TEST: %s" % ("PASS" if all_ok else "FAIL"))
		get_tree().quit(0 if all_ok else 1)
