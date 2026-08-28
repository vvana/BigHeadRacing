extends Node3D
## Автотест толчка игрок-игроку (протокол 11, жалоба 28.08 «при
## столкновении не могу его сдвинуть или поддеть»). Машины клиент-
## авторитетны: рикошет агрессора двигает только ЕГО машину, а жертве
## толчок доставляется событием через сервер (Car.apply_net_shove).
## Проверяем приёмную сторону:
##   1) толчок применяется: скорость вдоль dir и закрутка появились;
##   2) кап дикости: сближение 50 не разгоняет дичее рикошетного капа;
##   3) дедуп: если мой рикошет уже отработал контакт с этим агрессором
##      (_touch_mute свежий), событие о том же касании отбрасывается.

var _main: Node3D
var _victim: Car
var _attacker: Car
var _frame := 0
var _ok := {}


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 30:
		_victim = _main._cars[0]
		_attacker = _main._cars[1]
		for i in _main._cars.size():
			var c: Car = _main._cars[i]
			c.controls_enabled = false
			if i > 1:
				c.alive = false
				c.global_position = Vector3(150, 2, 150 + i * 8)
		_attacker.net_make_puppet()
		_victim.linear_velocity = Vector3.ZERO
		return
	if _frame == 40:
		_victim.apply_net_shove(null, Vector3(1, 0, 0), 10.0, 1.5)
		return
	if _frame == 41:
		_ok["толчок"] = _victim.linear_velocity.x > 2.5 \
				and absf(_victim.angular_velocity.y) > 0.4
		print("после события: v=%.1f м/с, закрутка %.2f (%s)"
				% [_victim.linear_velocity.x, _victim.angular_velocity.y,
				"ok" if _ok["толчок"] else "FAIL"])
		return
	if _frame == 60:
		_victim.linear_velocity = Vector3.ZERO
		_victim.apply_net_shove(null, Vector3(1, 0, 0), 50.0, 0.0)
		return
	if _frame == 61:
		_ok["кап"] = _victim.linear_velocity.length() < 8.5
		print("сближение 50 -> v=%.1f м/с (%s)"
				% [_victim.linear_velocity.length(),
				"ok" if _ok["кап"] else "FAIL"])
		return
	if _frame == 80:
		_victim.linear_velocity = Vector3.ZERO
		_victim._touch_mute[_attacker.get_instance_id()] = \
				float(Time.get_ticks_msec())
		_victim.apply_net_shove(_attacker, Vector3(1, 0, 0), 10.0, 1.5)
		return
	if _frame == 81:
		_ok["дедуп"] = _victim.linear_velocity.length() < 0.8
		print("дубль после своего рикошета: v=%.1f м/с (%s)"
				% [_victim.linear_velocity.length(),
				"ok" if _ok["дедуп"] else "FAIL"])
		var all_ok := _ok.values().all(func(v: Variant) -> bool: return v)
		print("SHOVE TEST: %s" % ("PASS" if all_ok else "FAIL — %s" % [_ok]))
		get_tree().quit(0 if all_ok else 1)
