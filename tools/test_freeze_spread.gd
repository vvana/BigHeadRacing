extends Node3D
## Автотест: ЗАМОРОЗКА ЕЗДИТ ПО СЕТИ И ЗАРАЖАЕТ.
##
## Жалоба 28.08: «я был замороженный, а мой друг по сети ехал впритык ко
## мне и не заморозился тоже». Причина: в снимке состояния (Main._pack_state
## → _rx_state) поля заморозки не было вовсе — на чужом экране у моей
## машины `_freeze_time` всегда ноль. Значит, и «синей» шубы не видно, и
## заразность (Car._bounce_off_cars) с ней не работает: там сравнивается
## именно `other._freeze_time`.
##
## Стенд проверяет обе половины цепочки:
##   1) ПРОТОКОЛ — сервер пакует снимок, клиент его разбирает, остаток
##      заморозки обязан доехать до марионетки (протокол 12);
##   2) ЗАРАЗНОСТЬ — своя машина таранит замороженную марионетку и обязана
##      перенять дебаф.
## До правки падает первая часть, а вместе с ней и вторая.
##
## Запуск: godot --headless --path . res://tools/TestFreezeSpread.tscn

const FREEZE := 3.0        # длительность дебафа (Projectile: ледышка даёт 3 с)
const APPROACH := 12.0     # с какой скоростью подъезжаем, м/с
const WATCH := 150         # кадров на сближение

var _main: Node3D
var _frame := 0
var _me: Car
var _victim: Car
var _dir := Vector3.ZERO
var _ok := {}
var _min_gap := 1e9
var _caught_at := -1


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 30:
		_me = _main._cars[0]
		_victim = _main._cars[1]
		# Лишние машины глушим и увозим, чтобы не лезли в замер.
		for i in range(2, _main._cars.size()):
			var extra: Car = _main._cars[i]
			extra.controls_enabled = false
			extra.alive = false
			extra.global_position = Vector3(150, 2, 150 + i * 8)
		_me.controls_enabled = false
		_victim.controls_enabled = false
		_victim.net_make_puppet()
		return
	if _frame == 40:
		_check_protocol()
		# Марионетка — в 9 м прямо по курсу, стоит поперёк (борт ко мне).
		_dir = -_me.global_transform.basis.z
		_dir.y = 0.0
		_dir = _dir.normalized()
		var at: Vector3 = _me.global_position + _dir * 9.0
		at.y = _me.global_position.y
		var across := Quaternion(Vector3.UP, PI * 0.5) \
				* _me.global_transform.basis.get_rotation_quaternion()
		_victim.net_apply_snapshot(at, across, Vector3.ZERO)
		_me.linear_velocity = _dir * APPROACH
		_me.reset_speed_memory()
		return
	if _frame > 40 and _frame <= 40 + WATCH:
		# Марионетка стоит на месте и остаётся замороженной: снимки идут
		# потоком, и каждый подтверждает остаток дебафа. Здесь их поток
		# заменяем руками — сети в стенде нет.
		_victim.net_apply_snapshot(_victim.global_position,
				_victim.global_transform.basis.get_rotation_quaternion(),
				Vector3.ZERO)
		_victim.net_set_freeze(FREEZE)
		# Касание меряем ТАК ЖЕ, как его видит игра: зазор капсул вдоль
		# кузовов (Car._capsule_gap), а не расстояние центров. У машины
		# длиной 3.2 м центры расходятся на 2.5 м при полном борт-в-борт.
		_min_gap = minf(_min_gap, _me._capsule_gap(_victim))
		if _caught_at < 0 and _me.freeze_left() > 0.0:
			_caught_at = _frame - 40
		return
	if _frame == 41 + WATCH:
		print("  зазор кузовов сошёлся до %.2f м (касание — ближе 1.7 м)"
				% _min_gap)
		_ok["дотянулись до соперника"] = _min_gap < 1.7
		_ok["заморозка перешла при касании"] = _caught_at >= 0
		if _caught_at >= 0:
			print("  дебаф перешёл на %d-м кадре сближения, остаток %.2f с"
					% [_caught_at, _me.freeze_left()])
		_report()


## Первая половина: снимок сервера доносит остаток заморозки до марионетки.
## Пакуем состояние ЗАМОРОЖЕННОЙ машины (как сервер), стираем дебаф у
## марионетки (как будто клиент о нём ничего не знает) и разбираем снимок
## (как клиент). Заморозка обязана вернуться.
func _check_protocol() -> void:
	_victim.apply_freeze(FREEZE)
	var packed: Array = _main._pack_state()
	# С протокола 13 байтов на машину ПЯТЬ: пятый — место в гонке (клиент
	# не может считать его сам без вранья, см. Main._pack_state). Стенду
	# важно, что байт заморозки едет и стоит четвёртым, — это ниже.
	_ok["в снимке 5 байт на машину"] = 			(packed[1] as PackedByteArray).size() == _main._cars.size() * 5
	_victim.net_set_freeze(0.0)
	_main._rx_state(packed[0], packed[1])
	var got := _victim.freeze_left()
	print("  снимок довёз заморозки: %.2f с из %.2f" % [got, FREEZE])
	# Байт хранит десятые доли секунды — допуск на округление.
	_ok["заморозка доехала в снимке"] = got > FREEZE - 0.15


func _report() -> void:
	var all_ok := true
	for k: String in _ok:
		if not _ok[k]:
			all_ok = false
		print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
	print("FREEZESPREAD TEST: %s" % ("PASS" if all_ok else "FAIL"))
	get_tree().quit(0 if all_ok else 1)
