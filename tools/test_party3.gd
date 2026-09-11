extends Node
## Стенд «КОМАНДА ИЗ ТРЁХ СЪЕЗЖАЕТСЯ В ЛОББИ» (09.09.2026, жалоба: «нас трое
## в команде, все нажимаем ГОТОВ, но третий не попадает в гонку и в лобби
## его нет»). Всё по-настоящему, в четырёх процессах: ворота (Main.tscn
## --server, в них же сервер друзей на своём порту) и три клиента
## TestPartyClient.tscn. Судья только запускает процессы, ждёт их итоги
## user://party3_<n>.txt и проверяет: у всех троих есть слот, порт один и
## тот же, и в момент «GO!» каждый видел троих живых.
## Ключи после «--»: --slow=<n> — клиент n «медленный телефон»
## (подключается через 3 с после go, сцену строит ещё 15 с);
## --join-delay=<с>/--load-delay=<с> — свои задержки для него.
## Запуск: godot --headless --path . res://tools/TestParty3.tscn [-- --slow=2]

const GATE_PORT := 29970
const SOCIAL_PORT := 29990
const LIMIT := 130.0

var _t := 0.0
var _gate_pid := -1
var _pids: Array[int] = []
var _clients_started := false
var _done := false
var _slow := -1
var _join_delay := 3.0
var _load_delay := 15.0


func _ready() -> void:
	Engine.max_fps = 60
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--slow="):
			_slow = int(a.trim_prefix("--slow="))
		elif a.begins_with("--join-delay="):
			_join_delay = float(a.trim_prefix("--join-delay="))
		elif a.begins_with("--load-delay="):
			_load_delay = float(a.trim_prefix("--load-delay="))
	for i in 3:
		var abs := ProjectSettings.globalize_path("user://party3_%d.txt" % i)
		if FileAccess.file_exists(abs):
			DirAccess.remove_absolute(abs)
	# Чужая визитка ворот стенда от прошлого прогона (процесс мёртв) —
	# Rooms.cards сама выкинет по сроку, но пусть не путает первые секунды.
	Rooms.remove_card(GATE_PORT)
	_gate_pid = _spawn("res://scenes/Main.tscn",
			"--server --port=%d --social-port=%d --track=grass"
			% [GATE_PORT, SOCIAL_PORT], "party3_gate")
	print("судья: ворота запущены, pid %d" % _gate_pid)


func _spawn(scene: String, args: String, out_name: String) -> int:
	var out := ProjectSettings.globalize_path("user://%s.out.txt" % out_name)
	return OS.create_process("cmd.exe", ["/c",
			"\"%s\" --headless --path \"%s\" %s -- %s > \"%s\" 2>&1"
			% [OS.get_executable_path(), ProjectSettings.globalize_path("res://"),
					scene, args, out]])


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if not _clients_started:
		# Ждём визитку ворот — сервер друзей ищет лобби по ней.
		var seen := false
		for c: Dictionary in Rooms.cards():
			if int(c.port) == GATE_PORT:
				seen = true
		if seen:
			_clients_started = true
			for i in 3:
				var extra := ""
				if i == _slow:
					extra = " --join-delay=%.1f --load-delay=%.1f" % [_join_delay, _load_delay]
				_pids.append(_spawn("res://tools/TestPartyClient.tscn",
						"%d %d%s" % [i, SOCIAL_PORT, extra], "party3_client_%d" % i))
			print("судья: визитка ворот есть (%.1f с), клиенты запущены: %s"
					% [_t, str(_pids)])
		elif _t > 30.0:
			_finish("ворота не подняли визитку за 30 с")
		return
	var results: Array = []
	for i in 3:
		var abs := ProjectSettings.globalize_path("user://party3_%d.txt" % i)
		if not FileAccess.file_exists(abs):
			break
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(abs))
		if typeof(data) != TYPE_DICTIONARY:
			break
		results.append(data)
	if results.size() == 3:
		_verdict(results)
	elif _t > LIMIT:
		_finish("клиенты не отчитались за %d с (есть %d из 3)" % [int(LIMIT), results.size()])


func _verdict(rs: Array) -> void:
	var fails := PackedStringArray()
	var port0 := int(rs[0].get("port", 0))
	for i in 3:
		var r: Dictionary = rs[i]
		print("клиент %d: %s" % [i, JSON.stringify(r)])
		if str(r.get("why", "")) != "go":
			fails.append("клиент %d не дождался GO: %s" % [i, r.get("why", "")])
		if int(r.get("slot", -1)) < 0:
			fails.append("клиент %d без слота" % i)
		if int(r.get("port", 0)) != port0:
			fails.append("клиент %d в другом заезде (порт %d, у первого %d)"
					% [i, int(r.get("port", 0)), port0])
		if int(r.get("humans", -1)) != 3:
			fails.append("клиент %d на старте видел живых: %d (надо 3)"
					% [i, int(r.get("humans", -1))])
	_finish("; ".join(fails))


func _finish(fail: String) -> void:
	if _done:
		return
	_done = true
	for p: int in _pids:
		OS.kill(p)
	if _gate_pid > 0:
		OS.kill(_gate_pid)
	# Комнаты, поднятые воротами, — отдельные процессы; их визитки живут в
	# user://rooms, по ним и гасим (Rooms помнит pid только у ворот).
	print("судья: логи — user://party3_gate.out.txt, party3_client_<n>.out.txt, party3_<n>.log")
	if fail == "":
		print("PARTY3 TEST: PASS")
	else:
		print("PARTY3 TEST: FAIL (%s)" % fail)
	get_tree().quit(0 if fail == "" else 1)
