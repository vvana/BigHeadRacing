extends Node
## Сетевой стенд п.9 (жалоба 04.09/07.09: «при уничтожении камера прыгает
## на того, кто тебя уничтожил, и возвращается после появления»).
## Оффлайн (TestCamDestroy) скачков нет — воспроизводим ПО СЕТИ: сервер
## живёт в этом процессе (корень сцены — Main с Main.gd, RPC адресуется по
## пути /root/Main, поэтому судья — дочерний узел, как у TestNet; его
## _ready идёт раньше родительского, там и поднимаем сервер), клиент —
## отдельным процессом (TestNetCamClient.tscn) на 127.0.0.1:PORT. Клиент
## едет с ботами, и они сами убивают его оружием (2-4 раза за 100 с);
## клиент каждый кадр смотрит, куда глядит камера и где его машина, и по
## таймеру кладёт итог в user://netcam_result.txt; здесь его читаем.
## Запуск: godot --headless --path . res://tools/TestNetCam.tscn

const PORT := 29981
const RESULT := "user://netcam_result.txt"
const KILLS := 3
const KILL_GAP := 8.0

# Сервер перезапускает сцену (reload_current_scene) при смене размера
# заезда/трассы — судья при этом создаётся заново: сервер и клиент
# поднимаем один раз (статические флаги переживают перезапуск сцены).
static var _server_up := false
static var _client_pid := -1

var _main: Node3D
var _t := 0.0
var _pid := -1
var _done := false
var _kills := 0
var _next_kill := -1.0
var _dbg_t := -9.0


func _ready() -> void:
	_main = get_parent()
	if _server_up:
		_pid = _client_pid
		print("судья: сцена сервера перезапущена, продолжаем")
		return
	_server_up = true
	Net.port = PORT
	# Размер заезда — как попросит клиент (GameState.race_size), иначе
	# сервер перестраивается под первого игрока и сцена перезапускается.
	Net.race_size = GameState.race_size
	Net.start_server()
	var abs := ProjectSettings.globalize_path(RESULT)
	if FileAccess.file_exists(abs):
		DirAccess.remove_absolute(abs)
	# Через cmd — чтобы вывод клиента (ошибки скриптов, падения) остался в
	# user://netcam_client_out.txt: у create_process его иначе не увидеть.
	var out := ProjectSettings.globalize_path("user://netcam_client_out.txt")
	_pid = OS.create_process("cmd.exe", ["/c",
			"\"%s\" --headless --path \"%s\" res://tools/TestNetCamClient.tscn -- %d > \"%s\" 2>&1"
			% [OS.get_executable_path(), ProjectSettings.globalize_path("res://"),
					PORT, out]])
	_client_pid = _pid
	print("судья: клиент запущен, pid %d" % _pid)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t > 120.0:
		_finish("клиент не доехал до трёх смертей за 120 с")
		return
	var abs := ProjectSettings.globalize_path(RESULT)
	if FileAccess.file_exists(abs):
		_finish("")
		return
	# Заезд идёт? (controls_enabled у марионетки клиента на сервере не
	# выставляется — смотрим флаг старта.)
	var cars: Array = _main._cars
	if int(_t * 10.0) % 100 == 0 and _t - _dbg_t > 1.0:
		_dbg_t = _t
		var taken := ""
		for b in _main._slot_taken:
			taken += "1" if b else "0"
		var st := ""
		for c in cars:
			st += "%s%s " % ["A" if (c as Car).alive else "d", "g" if (c as Car).is_ghost() else ""]
		print("судья t=%.0f: started=%s taken=%s cars=%s kills=%d next=%.0f"
				% [_t, _main._net_started, taken, st, _kills, _next_kill])
	if cars.is_empty() or not _main._net_started:
		return
	# Слот клиента — из реестра пиров (server-side _slot_taken не ведётся).
	var slot: int = -1
	for peer in Net.slot_of_peer:
		slot = int(Net.slot_of_peer[peer])
	if slot < 0:
		return
	# Боты убивают и сами, но не всегда успевают за 100 с — добавляем
	# три гарантированных: бот встаёт за спиной клиента и бьёт лазером.
	if _next_kill < 0.0:
		_next_kill = _t + 6.0
	if _kills >= KILLS or _t < _next_kill:
		return
	var victim: Car = cars[slot]
	if not victim.alive or victim.is_ghost():
		return
	var killer: Car = null
	for i in cars.size():
		if i != slot and (cars[i] as Car).alive and not (cars[i] as Car).is_ghost():
			killer = cars[i]
			break
	if killer == null:
		return
	var fwd := -victim.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD
	killer.global_transform = Transform3D(Basis.looking_at(fwd),
			victim.global_position - fwd * 8.0 + Vector3.UP * 0.3)
	killer.linear_velocity = victim.linear_velocity
	killer._use_laser(fwd)
	_kills += 1
	_next_kill = _t + KILL_GAP
	print("сервер: лазер бота %d по клиенту (слот %d), t=%.1f" % [cars.find(killer), slot, _t])


func _finish(err: String) -> void:
	_done = true
	# Даём клиенту дописать итог (он пишет его, когда сервер пропал или
	# по своему таймеру), затем читаем.
	Net.leave()
	await get_tree().create_timer(4.0).timeout
	if OS.is_process_running(_pid):
		OS.kill(_pid)
	var abs := ProjectSettings.globalize_path(RESULT)
	var text := ""
	if FileAccess.file_exists(abs):
		text = FileAccess.get_file_as_string(abs)
	print(text)
	var ok := err.is_empty() and text.contains("NETCAM CLIENT: PASS")
	if not err.is_empty():
		print("  ошибка стенда: %s" % err)
	print("NETCAM TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
