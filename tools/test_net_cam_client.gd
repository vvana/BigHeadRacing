extends Node
## Клиентская половина TestNetCam (см. test_net_cam.gd): корень сцены —
## Main с Main.gd (RPC адресуется по пути /root/Main, как у TestNet), этот
## узел — дочерний проверяльщик. Подключается к 127.0.0.1:<порт из
## аргумента>, держит газ и после каждого взрыва своей машины следит за
## ЦЕЛЬЮ КАМЕРЫ (положение камеры минус её отступ): пока машина в паузе
## появления/призраком, цель не должна уходить от места взрыва дальше
## JUMP_TOL и не должна оказываться у чужой машины.

const JUMP_TOL := 6.0
const RESULT := "user://netcam_result.txt"
const LOG := "user://netcam_client.log"

# Клиентская сцена тоже перезапускается (сервер выбрал трассу —
# _rx_track → reload_current_scene): соединение держим одно, а ход
# проверки — в статических полях, чтобы пережить перезапуск.
static var _joined := false
static var _log_started := false

var _main: Node3D
var _t := 0.0
var _dead_prev := false
var _death_pos := Vector3.ZERO
var _deaths := 0
var _worst := 0.0
var _jumps: Array[String] = []
var _written := false
var _going := false
var _trace_left := 0.0
var _go_t := -1.0
var _prev_d := 999.0


func _ready() -> void:
	_main = get_parent()
	Engine.max_fps = 120
	var args := OS.get_cmdline_user_args()
	var port := int(args[0]) if args.size() > 0 else 29981
	_log("probe ready, joined=%s my_slot=%d" % [_joined, Net.my_slot])
	Net.left.connect(_on_left)
	if _joined:
		return
	_joined = true
	Net.join_failed.connect(func(r: String) -> void: _write("FAIL: нет связи: " + r))
	Net.join_server("127.0.0.1", port, false)


func _log(line: String) -> void:
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE if _log_started
			and FileAccess.file_exists(LOG) else FileAccess.WRITE)
	_log_started = true
	if f == null:
		return
	f.seek_end()
	f.store_line("%.1f %s" % [Time.get_ticks_msec() / 1000.0, line])
	f.close()


func _physics_process(delta: float) -> void:
	_t += delta
	# Заезд с ботами: они сами убивают нас оружием (2-4 раза за 100 с) —
	# по таймеру подводим итог.
	if _t > 100.0 and not _written:
		_write("")
		return
	if Net.my_slot < 0 or _main._car == null:
		return
	if _main._car.controls_enabled:
		if not _going:
			_going = true
			_go_t = _t
			_log("controls on, slot %d, role %d" % [Net.my_slot, _main._car.net_role])
		Input.action_press("accelerate")


func _process(delta: float) -> void:
	if _written or Net.my_slot < 0 or _main._car == null:
		return
	var cam := _main.get_node_or_null("IsoCamera") as IsoCamera
	if cam == null:
		return
	var car: Car = _main._car
	var target: Vector3 = cam.global_position - cam._look_offset
	# «Мёртвая» фаза для суда — только пауза появления: призрак уже едет
	# сам, и камера за ним — это не скачок. Но траекторию пишем шире:
	# от взрыва до секунды после появления (видно, куда и когда ушла).
	var paused := car.is_respawning()
	# Первые секунды после старта не судим: сервер сам расставляет машины
	# по решётке (телепорт _rx_start), и камера ещё летит к своей машине.
	if _go_t < 0.0 or _t < _go_t + 3.0:
		_dead_prev = paused
		return
	if paused and not _dead_prev:
		_deaths += 1
		_prev_d = 999.0
		_death_pos = car.global_position
		_trace_left = 1.5
		print("клиент: смерть %d на t=%.1f в %s" % [_deaths, _t, _death_pos])
		_log("death %d at %s, camera target %s" % [_deaths, _death_pos, target])
	if _trace_left > 0.0:
		_trace_left -= delta
		_log("  t=%.2f target=%s car=%s visual=%s paused=%s ghost=%s alive=%s"
				% [_t, target, car.global_position, car.visual_origin(),
						paused, car.is_ghost(), car.alive])
	if paused:
		var d := Vector2(target.x - _death_pos.x, target.z - _death_pos.z).length()
		_worst = maxf(_worst, d)
		# Скачок — это когда камера УХОДИТ от места взрыва (растёт d) или
		# оказалась дальше 10 м; первые кадры после гибели она ещё догоняет
		# машину с отставания 5-7 м на скорости — это не скачок.
		var away := d > JUMP_TOL and d > _prev_d + 0.02
		_prev_d = d
		if away or d > 10.0:
			var near := ""
			for i in _main._cars.size():
				var c: Car = _main._cars[i]
				if c == car:
					continue
				var dc := Vector2(target.x - c.global_position.x,
						target.z - c.global_position.z).length()
				if dc < 6.0:
					near = " (рядом машина %d, %.1f м)" % [i, dc]
			_jumps.append("смерть %d, t=%.2f: камера в %.1f м от места взрыва%s, машина в %s"
					% [_deaths, _t, d, near, car.global_position])
	_dead_prev = paused


func _on_left() -> void:
	_write("")


func _write(err: String) -> void:
	if _written:
		return
	_written = true
	var ok := err.is_empty() and _deaths >= 1 and _jumps.is_empty()
	var lines := PackedStringArray()
	lines.append("смертей: %d, худший уход камеры от места взрыва: %.1f м" % [_deaths, _worst])
	for j in _jumps.slice(0, 12):
		lines.append("  " + j)
	if not err.is_empty():
		lines.append("  " + err)
	lines.append("NETCAM CLIENT: %s" % ("PASS" if ok else "FAIL"))
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	print("\n".join(lines))
	get_tree().quit(0 if ok else 1)
