extends Node3D
## Автотест ПЕРЕПРИВЯЗКИ ПЛЕЕРА после фриза СВОЕГО кадра (21.09, браузер):
## «на старте соперники стоят, отъезжают назад, потом разом дёргаются, а их
## снаряды уже летят». Кадр клиента стоял секунды (компиляция шейдеров), снимки
## приехали пачкой, а плеер записи (_follow_buffered) нагонял их темпом +15% —
## картинка соперника жила в прошлом десятки секунд. Здесь: секунда ровной
## записи, затем ПАЧКА на 4 с разом (как после фриза), затем секунда ровной —
## и картинка обязана идти не дальше буфера от свежего снимка.

const SPEED := 10.0

var _main: Node3D
var _frame := 0
var _puppet: Car
var _base := Vector3.ZERO
var _dir := Vector3.FORWARD
var _rot := Quaternion.IDENTITY
var _n := 0            # сколько снимков подано
var _last := Vector3.ZERO


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _feed() -> void:
	_n += 1
	_last = _base + _dir * SPEED * (float(_n) / 60.0)
	_puppet.net_apply_snapshot(_last, _rot, _dir * SPEED, 5000.0 + float(_n))


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 30:
		_puppet = _main._cars[1]
		for i in _main._cars.size():
			var c: Car = _main._cars[i]
			c.controls_enabled = false
			if i != 1:
				c.alive = false
				c.global_position = Vector3(150, 2, 150 + i * 8)
				c.linear_velocity = Vector3.ZERO
		_base = _puppet.global_position
		_dir = -_puppet.global_transform.basis.z
		_dir.y = 0.0
		_dir = _dir.normalized()
		_rot = _puppet.global_transform.basis.get_rotation_quaternion()
		_puppet.net_make_puppet()
		Net.mode = Net.Mode.CLIENT
		Car.net_reset_buf_delay()
		return
	if _puppet == null:
		return
	if _frame <= 90:
		_feed()                      # секунда ровной записи
	elif _frame == 91:
		for k in 240:                # фриз 4 с: пачка разом
			_feed()
	elif _frame <= 151:
		_feed()                      # ещё секунда ровной
	else:
		var lag := (_last - _puppet.global_position).dot(_dir)
		print("отставание картинки от свежего снимка: %.1f м (буфер %.2f с)"
				% [lag, Car.net_buf_delay])
		# Норма — буфер (до 0.35 с = 3.5 м) минус упреждение; с багом ~15 м
		# (картинка стоит на самой старой записи, полторы секунды назад).
		var ok := lag < 6.0 and lag > -6.0
		print("STALL RESYNC TEST: %s" % ("PASS" if ok else "FAIL — %.1f м" % lag))
		get_tree().quit(0 if ok else 1)
