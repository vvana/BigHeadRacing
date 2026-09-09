extends Node3D
## Автотест: ДЫМ ИЗ-ПОД КОЛЁС ЕЗДИТ ПО СЕТИ (протокол 22, жалоба 09.09
## «у других машин нет эффектов дыма»). На клиенте все соперники —
## марионетки, их _physics_process до расчёта дыма не доходит, поэтому
## дым едет битом 4 второго байта снимка (Main._pack_state → _rx_state).
## Проверяем: 1) бот с дымом (debug_smoke) даёт бит в снимке, без дыма —
## нет; 2) марионетка по net_set_smoke зажигает и гасит эмиттеры;
## 3) серверная марионетка живого игрока судит по присланной скорости:
## боковой снос на ходу — дымит, прямой ход — нет, полёт — нет.
## Запуск: godot --headless --path . res://tools/TestSmokeNet.tscn

var _main: Node3D
var _frame := 0
var _ok := {}


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 30:
		for i in _main._cars.size():
			(_main._cars[i] as Car).controls_enabled = false
		(_main._cars[1] as Car).debug_smoke = true
		(_main._cars[1] as Car).debug_skid = true
		# Как на ВЫДЕЛЕННОМ сервере: эмиттеров у бота нет вовсе (_build_smoke
		# там не зовётся). Бит в снимке всё равно обязан быть — первая
		# версия судила по _smoke[0].emitting и на VDS молчала (09.09).
		for p in (_main._cars[1] as Car)._smoke:
			p.queue_free()
		(_main._cars[1] as Car)._smoke.clear()
		return
	if _frame != 45:
		return
	var packed: Array = _main._pack_state()
	var flags: PackedByteArray = packed[1]
	_ok["бот с дымом — бит 4 в снимке"] = (int(flags[1 * 6 + 1]) & 4) != 0
	_ok["бот без дыма — бита нет"] = (int(flags[2 * 6 + 1]) & 4) == 0
	_ok["живой без дыма — бита нет"] = (int(flags[0 * 6 + 1]) & 4) == 0
	_ok["бот со следом — бит 8 в снимке"] = (int(flags[1 * 6 + 1]) & 8) != 0
	_ok["бот без следа — бита 8 нет"] = (int(flags[2 * 6 + 1]) & 8) == 0
	# Марионетка на клиенте: эмиттеры ставятся по снимку.
	var puppet: Car = _main._cars[2]
	puppet.net_make_puppet()
	puppet.net_set_smoke(true)
	_ok["марионетка: net_set_smoke(true) зажгла"] = puppet._smoke.size() > 0 \
			and puppet._smoke[0].emitting
	puppet.net_set_smoke(false)
	_ok["марионетка: net_set_smoke(false) погасила"] = not puppet._smoke[0].emitting
	# Серверная марионетка живого игрока: по присланной скорости.
	var p: Car = _main._cars[3]
	p.net_make_puppet()
	var rot: Quaternion = p.global_transform.basis.get_rotation_quaternion()
	var fwd: Vector3 = -p.global_transform.basis.z
	var right: Vector3 = p.global_transform.basis.x
	var pos: Vector3 = p.global_position
	p.net_apply_snapshot(pos, rot, fwd * 20.0, 10.0)
	_ok["марионетка: прямой ход — не дымит"] = not p.smoke_bit()
	p.net_apply_snapshot(pos, rot, fwd * 12.0 + right * 8.0, 11.0)
	_ok["марионетка: боковой снос 8 м/с на ходу — дымит"] = p.smoke_bit()
	p.net_apply_snapshot(pos, rot, fwd * 12.0 + right * 8.0 + Vector3.UP * 5.0, 12.0)
	_ok["марионетка: в полёте — не дымит"] = not p.smoke_bit()
	p.net_apply_snapshot(pos, rot, fwd * 3.0 + right * 2.0, 13.0)
	_ok["марионетка: медленный снос — не дымит"] = not p.smoke_bit()
	p.alive = false
	p.net_apply_snapshot(pos, rot, fwd * 12.0 + right * 8.0, 14.0)
	_ok["уничтоженная — не дымит"] = not p.smoke_bit()
	# СЛЕД ШИН (бит 8, 09.09 «след от шин других машин нужно тоже
	# отображать»): та же цепочка, что у дыма.
	p.alive = true
	p.net_apply_snapshot(pos, rot, fwd * 20.0, 14.5)
	_ok["марионетка: прямой ход — следа нет"] = not p.skid_bit()
	p.net_apply_snapshot(pos, rot, fwd * 12.0 + right * 8.0, 15.0)
	_ok["марионетка: снос 8 м/с при 14 м/с — след"] = p.skid_bit()
	p.net_apply_snapshot(pos, rot, fwd * 8.0 + right * 6.0, 16.0)
	_ok["марионетка: снос 6 м/с при 10 м/с — следа нет (порог выше дымового)"] = 			not p.skid_bit() and p.smoke_bit()
	p.net_set_skid(true)
	_ok["марионетка: net_set_skid(true) включил признак"] = p._skid_active
	p.net_set_skid(false)
	_ok["марионетка: net_set_skid(false) выключил"] = not p._skid_active
	var all_ok := true
	for k in _ok:
		print("  %s  %s" % ["ok  " if _ok[k] else "FAIL", k])
		all_ok = all_ok and bool(_ok[k])
	print("SMOKE NET TEST: %s" % ("PASS" if all_ok else "FAIL"))
	get_tree().quit(0 if all_ok else 1)
