extends Node3D
## Автотест СМЕНЫ ЧАСОВ АВТОРА в метках тиков (протокол 9): «мы с игроком
## по сети друг у друга стоим на месте» (27.08). Пока владелец машины не
## прислал ни одного состояния, сервер метит её снимки СВОИМИ часами — на
## VDS они на часы больше часов свежезапущенного клиента. Затем метки
## становятся часами ВЛАДЕЛЬЦА (маленькими), и дедупликация
## `stamp <= _snap_stamp` в net_apply_snapshot выбрасывала ВСЕ его состояния
## как «старые» — машина игрока замирала навсегда. На локалхосте сервер
## старше клиента на секунды, разрыв часов самозалечивался — стенды молчали.
## Здесь разрыв делаем честно большим и проверяем, что после смены часов
## марионетка ЕДЕТ по присланной записи.

const SRV0 := 1000000.0   # «часы сервера»: работает давно
const OWN0 := 600.0       # «часы владельца»: игра запущена только что
const SPEED := 10.0       # м/с в присланных состояниях фазы Б

var _main: Node3D
var _frame := 0
var _puppet: Car
var _base := Vector3.ZERO
var _rot := Quaternion.IDENTITY
var _stood := -1.0        # смещение к концу фазы А (должно быть ~0)


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


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
		_rot = _puppet.global_transform.basis.get_rotation_quaternion()
		_puppet.net_make_puppet()
		# Буфер воспроизведения — путь клиента; включаем его роль руками
		# (пира нет, но ни Main, ни Car без my_slot к сети не обращаются).
		Net.mode = Net.Mode.CLIENT
		return
	if _puppet == null:
		return
	# Фаза А (1 с): машина стоит на решётке, снимки метит СЕРВЕР.
	if _frame > 30 and _frame <= 90:
		_puppet.net_apply_snapshot(_base, _rot, Vector3.ZERO,
				SRV0 + float(_frame - 30))
		if _frame == 90:
			_stood = _puppet.global_position.distance_to(_base)
		return
	# Фаза Б (4 с): владелец поехал — метки стали ЕГО часами (меньше!).
	if _frame > 90 and _frame <= 330:
		var n := _frame - 90
		var pos := _base + Vector3(1, 0, 0) * SPEED * (float(n) / 60.0)
		_puppet.net_apply_snapshot(pos, _rot, Vector3(SPEED, 0, 0),
				OWN0 + float(n))
		return
	if _frame == 331:
		var moved := _puppet.global_position.distance_to(_base)
		print("фаза А: смещение %.2f м (стоит); фаза Б: уехала на %.2f м"
				% [_stood, moved])
		# С багом все состояния владельца отбрасываются: moved ~ 0.
		var ok := _stood < 1.0 and moved > 5.0
		print("STAMPSWAP TEST: %s" % ("PASS" if ok
				else "FAIL — stood=%.2f moved=%.2f" % [_stood, moved]))
		get_tree().quit(0 if ok else 1)
