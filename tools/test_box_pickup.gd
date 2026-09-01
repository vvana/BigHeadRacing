extends Node3D
## Автотест ПОДБОРА БОКСА машиной живого игрока (жалоба 28.08: «иногда
## проезжаю не собирая кубы, хотя кажется что задеваю»).
##
## На сервере машина игрока — марионетка, и её ТЕЛО ведётся сглаженно
## (_follow_snapshot: подтяжка с постоянной времени + упреждение). На
## поворотах и при рывках канала сглаженный путь идёт в стороне от
## настоящего на десятки сантиметров, а куб всего 1.3 м — Area3D его и
## промахивала. Теперь сервер проверяет подбор по СЫРЫМ данным владельца
## (Car.true_position).
##
## Сценарий: машина едет мимо куба по сырым данным ТОЧНО через него, а
## тело искусственно смещено вбок (имитируем хвост сглаживания).
##
## Фаза 2 (жалоба 01.09 «по сети машины по-прежнему проезжают сквозь
## бонус»): снимки владельца приходят реже кадров сервера, и сырая точка
## ПЕРЕШАГИВАЕТ куб — снимок за 4 м ДО куба, следующий в 4 м ЗА ним.
## Точечная проверка мазала; замёт отрезка между снимками обязан выдать.

var _main: Node3D
var _car: Car
var _box: WeaponBox
var _box2: WeaponBox
var _dir := Vector3.FORWARD
var _frame := 0
var _got := false


func _ready() -> void:
	Net.port = 29981
	Net.start_server()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 30:
		_car = _main._cars[0]
		for i in _main._cars.size():
			var c: Car = _main._cars[i]
			c.controls_enabled = false
			if i > 0:
				c.alive = false
				c.global_position = Vector3(150, 2, 150 + i * 8)
		_car.net_make_puppet()
		# Глушим собственную подтяжку тела: стенду нужно РАЗВЕСТИ сырые
		# данные и тело, а _follow_snapshot вернул бы тело к снимку.
		_car.set_physics_process(false)
		_car.weapon = -1
		# Бокс СТАВИМ ВПЕРЕДИ: если создать его прямо на машине, Area3D
		# засчитает вход ещё до того, как стенд разведёт тело и сырые
		# данные, и проверка позеленеет вхолостую (поймано 28.08).
		var f: Vector3 = -_car.global_transform.basis.z
		f.y = 0.0
		_box = WeaponBox.new()
		_main.add_child(_box)
		_box.global_position = _car.global_position 				+ f.normalized() * 10.0 + Vector3(0, 0.5, 0)
		return
	if _car == null or _box == null:
		return
	if _frame > 30 and _frame <= 60:
		# СЫРОЕ состояние владельца — точно на кубе; ТЕЛО уводим на 1.2 м
		# вбок, как это делает хвост сглаживания.
		_car.net_apply_snapshot(_box.global_position - Vector3(0, 0.5, 0),
				_car.global_transform.basis.get_rotation_quaternion(),
				Vector3.ZERO, 5000.0 + float(_frame))
		_car.global_position = _box.global_position \
				+ _car.global_transform.basis.x * 2.5 - Vector3(0, 0.5, 0)
		# Признак берём ПРЯМОЙ — отметку выдачи в самом боксе. По полю
		# weapon судить нельзя: игра выдаёт машинам стартовое оружие, и
		# стенд «зеленел» бы и без подбора.
		if _box._next_pickup.has(_car.get_instance_id()):
			_got = true
		return
	if _frame == 61:
		print("бокс отметил выдачу: %s" % str(_got))
		return
	# ---- Фаза 2: сырые точки ПЕРЕШАГИВАЮТ куб (снимки реже кадров). ----
	if _frame == 70:
		var f2: Vector3 = -_car.global_transform.basis.z
		f2.y = 0.0
		_dir = f2.normalized()
		_box2 = WeaponBox.new()
		_main.add_child(_box2)
		_box2.global_position = _car.global_position \
				+ _dir * 30.0 + Vector3(0, 0.5, 0)
		return
	if _frame == 75:
		# Снимок за 4 м ДО куба (бокс запомнит эту точку)...
		_snap_to(_box2.global_position - _dir * 4.0)
		return
	if _frame == 80:
		# ...следующий — в 4 м ЗА кубом: ни одна ТОЧКА куб не задевает
		# (зазор 4 м при пороге 1.5), выдать обязан замёт отрезка.
		_snap_to(_box2.global_position + _dir * 4.0)
		return
	if _frame == 90:
		var got2: bool = _box2._next_pickup.has(_car.get_instance_id())
		print("перешагнутый куб выдан: %s" % str(got2))
		print("BOXPICKUP TEST: %s" % ("PASS" if _got and got2
				else "FAIL — куб задет по сырым данным, а бонус не выдан"))
		get_tree().quit(0 if _got and got2 else 1)


## Скормить машине сырой снимок владельца в точке p (тело не трогаем).
func _snap_to(p: Vector3) -> void:
	_car.net_apply_snapshot(p - Vector3(0, 0.5, 0),
			_car.global_transform.basis.get_rotation_quaternion(),
			Vector3.ZERO, 5000.0 + float(_frame))
