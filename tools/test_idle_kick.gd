extends Node3D
## Стенд 22.09: выброс за бездействие (Main._tick_idle_kick) и запрет входа
## до конца покинутого заезда (Rooms.mark_left из Main._on_peer_left).
## Сцена оффлайн, Net.mode = SERVER, «живые игроки» — фальшивые пиры 777
## (слот 1) и 778 (слот 2), их машины — марионетки; порог _idle_kick 1.5 с.
##   1) стоящая машина слота 1 → через ~2 с выброс с причиной «без движения»;
##   2) машина, которую двигают снимками, выброса не получает;
##   3) уход из идущего заезда пишет запись: left_until(uid) в будущем, срок
##      ≤ 480 + 40 с; clear_left порта снимает её;
##   4) уход до старта (лобби) записи не даёт; уход доехавшего — тоже.
## Запуск: godot --headless --path . res://tools/TestIdleKick.tscn
## Вердикт — «IDLE KICK TEST: PASS|FAIL».

var _main: Node3D
var _frame := 0
var _ok := {}
var _p1: Car
var _p2: Car
var _x := 0.0


func _ready() -> void:
	process_physics_priority = 100
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _check(name: String, cond: bool, note := "") -> void:
	_ok[name] = cond
	print("  %s  %s%s" % ["ok  " if cond else "FAIL", name,
			("" if cond or note == "" else " — " + note)])


func _physics_process(_d: float) -> void:
	_frame += 1
	var cars: Array = _main._cars
	if cars.size() < 3 or _frame < 30:
		return
	if _frame == 30:
		for c: Car in cars:
			c.controls_enabled = false
		_p1 = cars[1]
		_p2 = cars[2]
		_p1.net_make_puppet()
		_p2.net_make_puppet()
		Net.mode = Net.Mode.SERVER
		Net.slot_of_peer[777] = 1
		Net.slot_of_peer[778] = 2
		_main._hello_done[1] = true
		_main._hello_done[2] = true
		_main._uid_of_slot[1] = "stand_idle_1"
		_main._uid_of_slot[2] = "stand_idle_2"
		_main._net_started = true
		_main._go_ms = Time.get_ticks_msec()
		_main._idle_kick = 1.5
		Rooms.clear_left(Net.port)
		return
	if _frame > 30 and _frame <= 210:
		# Слот 2 всё время «едет» снимками (0.3 м/кадр), слот 1 стоит.
		_x += 0.3
		var at: Vector3 = _p2.global_position + Vector3(0.3, 0.0, 0.0)
		_p2.net_apply_snapshot(at,
				_p2.global_transform.basis.get_rotation_quaternion(),
				Vector3(18.0, 0.0, 0.0))
		if _frame == 210:
			_check("стоящий слот 1 выброшен за бездействие",
					_main._last_kick.contains("без движения"),
					"причина: «%s»" % _main._last_kick)
			_check("едущий слот 2 не выброшен", _main._idle_since.has(2)
					or not _main._idle_pos.has(1) and Net.slot_of_peer.has(778))
		return
	if _frame == 220:
		# Выброс на сервере кончается разрывом соединения → _on_peer_left.
		Net.slot_of_peer.erase(777)
		_main._on_peer_left(777, 1)
		var now := Time.get_unix_time_from_system()
		var u := Rooms.left_until("stand_idle_1")
		_check("уход из идущего заезда закрыл вход", u > now,
				"until-now=%.1f" % (u - now))
		_check("срок в разумных пределах", u - now <= 520.0 and u - now >= 30.0,
				"until-now=%.1f" % (u - now))
		Rooms.clear_left(Net.port)
		_check("clear_left снял запись", Rooms.left_until("stand_idle_1") == 0.0)
		return
	if _frame == 230:
		# Доехавший — не «вышел, не доехав».
		_main._finish_order.append(2)
		Net.slot_of_peer.erase(778)
		Net.slot_of_peer[779] = 1   # чтобы сервер не решил «игроков не осталось»
		_main._on_peer_left(778, 2)
		_check("доехавший записи не получает",
				Rooms.left_until("stand_idle_2") == 0.0)
		# До старта (лобби) — тоже нет.
		_main._net_started = false
		_main._uid_of_slot[1] = "stand_idle_3"
		_main._hello_done[1] = true
		_main._on_peer_left(779, 1)
		_check("уход из лобби записи не даёт",
				Rooms.left_until("stand_idle_3") == 0.0)
		Rooms.clear_left(Net.port)
		var all_ok := true
		for k in _ok:
			all_ok = all_ok and bool(_ok[k])
		print("IDLE KICK TEST: %s" % ("PASS" if all_ok else "FAIL"))
		get_tree().quit(0 if all_ok else 1)
