extends Node
## Клиент стенда «команда из трёх съезжается в лобби» (см. test_party3.gd).
## Отдельный процесс на каждого «игрока»: выходит на связь с сервером
## друзей стенда (127.0.0.1:<social>), первый зовёт двух остальных по
## имени, те принимают, все жмут «ГОТОВ», по go едут в заезд ровно так,
## как CarSelect._on_party_go, и следят за лобби до «GO!». Итог — файл
## user://party3_<n>.txt (слот, порт, сколько живых в момент старта).
## Аргументы после «--»: <n 0..2> <social_port> [--join-delay=с]
## [--load-delay=с] — задержки «медленного телефона»: между go и
## подключением к заезду и между подключением и готовой сценой.
## Запуск руками: godot --headless --path . res://tools/TestPartyClient.tscn -- 0 29990

const NAMES := ["СтендК1", "СтендК2", "СтендК3"]
const LIMIT := 100.0


class Watcher:
	extends Node

	var idx := 0
	var sport := 29990
	var join_delay := 0.0
	var load_delay := 0.0
	var t := 0.0
	var invited := false
	var ready_sent := false
	var go_at := -1.0
	var joined_at := -1.0
	var scene_at := -1.0
	var welcome_at := -1.0
	var done := false
	var last_status := ""
	var last_slot := -99
	var last_taken := -1
	var log_f: FileAccess
	var wall0 := 0.0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		wall0 = Time.get_unix_time_from_system()
		log_f = FileAccess.open("user://party3_%d.log" % idx, FileAccess.WRITE)
		var abs := ProjectSettings.globalize_path("user://party3_%d.txt" % idx)
		if FileAccess.file_exists(abs):
			DirAccess.remove_absolute(abs)
		# Свой uid у каждого процесса (все три делят один user://profile),
		# постоянный между прогонами — реестр имён сервера друзей привязывает
		# имя к uid, и случайный uid получал бы «имя занято».
		GameState.uid = "party3_client_%d_stable" % idx
		GameState.player_name = NAMES[idx]
		Net.host = "127.0.0.1"
		Social.connected_changed.connect(func(on: bool) -> void:
			_log("social connected=%s" % on))
		Social.welcome.connect(func(ok: bool, reason: String) -> void:
			_log("welcome ok=%s reason=%s" % [ok, reason]))
		Social.invite_received.connect(_on_invite)
		Social.party_changed.connect(_on_party)
		Social.go.connect(_on_go)
		Social.notice.connect(func(txt: String) -> void: _log("notice: " + txt))
		Net.joined.connect(_on_joined)
		Net.join_failed.connect(func(r: String) -> void:
			_log("join_failed: " + r)
			_finish("join_failed"))
		Net.left.connect(func() -> void: _log("net left"))
		Social.go_online("127.0.0.1", sport)
		_log("start: %s uid=%s social=%d join_delay=%.1f load_delay=%.1f"
				% [NAMES[idx], GameState.uid, sport, join_delay, load_delay])

	func _log(s: String) -> void:
		# Два времени: t — сумма delta (под нагрузкой Godot её режет, до
		# 8 физ. шагов на кадр), и настенные часы — по ним сверять с
		# другими процессами.
		var wall := Time.get_unix_time_from_system() - wall0
		var line := "[%6.2f | %6.2f] %s" % [t, wall, s]
		print("[party3-%d] %s" % [idx, line])
		if log_f:
			log_f.store_line(line)
			log_f.flush()

	func _on_invite(from: String, count: int) -> void:
		_log("invite from %s (%d) — принимаем" % [from, count])
		Social.accept_invite()

	func _on_party() -> void:
		var ms := Social.members()
		var desc := PackedStringArray()
		for m: Dictionary in ms:
			desc.append("%s%s" % [str(m.get("name", "")),
					"✓" if bool(m.get("ready", false)) else ""])
		_log("party: %s launching=%s" % [", ".join(desc),
				Social.party.get("launching", false)])
		if ms.size() == 3 and not ready_sent:
			ready_sent = true
			_log("жмём ГОТОВ (size=%d)" % GameState.race_size)
			Social.set_ready(true)

	func _on_go(port: int, size: int, party_id: String, count: int) -> void:
		go_at = t
		_log("go: port=%d size=%d party=%s count=%d" % [port, size, party_id, count])
		if join_delay > 0.0:
			await get_tree().create_timer(join_delay).timeout
		# Как CarSelect._on_party_go.
		Net.leave()
		GameState.track_kind = ""
		Net.race_size = clampi(size, GameState.RACE_SIZE_MIN, GameState.RACE_SIZE_MAX)
		Net.want_size = Net.race_size
		Net.party_id = party_id
		Net.party_size = count
		Net.redirect_hops = 0
		_log("join_server 127.0.0.1:%d" % port)
		if not Net.join_server("127.0.0.1", port, false):
			_finish("join_server false")
			return
		await get_tree().create_timer(Net.CONNECT_TIMEOUT).timeout
		if joined_at < 0.0 and not done:
			_log("CONNECT_TIMEOUT: сервер заезда не ответил")
			_finish("connect_timeout")

	func _on_joined() -> void:
		joined_at = t
		_log("joined (ENet)")
		if load_delay > 0.0:
			await get_tree().create_timer(load_delay).timeout
		GameState.track_kind = ""
		scene_at = t
		get_tree().change_scene_to_file("res://scenes/Main.tscn")

	func _process(delta: float) -> void:
		t += delta
		if done:
			return
		if t > LIMIT:
			_finish("timeout")
			return
		if idx == 0 and not invited and Social.connected and Social.name_ok \
				and t > 4.0:
			invited = true
			_log("зовём %s и %s" % [NAMES[1], NAMES[2]])
			Social.invite(NAMES[1])
			Social.invite(NAMES[2])
		var main: Node = get_tree().root.get_node_or_null("Main")
		if main == null:
			return
		var slot: int = Net.my_slot
		if slot != last_slot:
			last_slot = slot
			if slot >= 0 and welcome_at < 0.0:
				welcome_at = t
			_log("my_slot=%d port=%d cars=%d" % [slot, Net.port, main._cars.size()])
		var taken := _taken(main)
		if taken != last_taken:
			last_taken = taken
			_log("живых в лобби: %d, маска %s" % [taken, str(main._slot_taken)])
		var lobby: Node = main._lobby
		if lobby != null and lobby._status != null:
			var st: String = lobby._status.text.replace("\n", " | ")
			if st != last_status:
				last_status = st
				_log("лобби: " + st)
		if slot >= 0 and slot < main._cars.size() \
				and main._cars[slot].controls_enabled:
			_log("GO! живых=%d слот=%d порт=%d" % [taken, slot, Net.port])
			_finish("go")

	func _taken(main: Node) -> int:
		var n := 0
		for v: bool in main._slot_taken:
			if v:
				n += 1
		return n

	func _finish(why: String) -> void:
		if done:
			return
		done = true
		var main: Node = get_tree().root.get_node_or_null("Main")
		var taken := _taken(main) if main != null else -1
		var res := {why = why, slot = Net.my_slot, port = Net.port, humans = taken,
				go_at = go_at, joined_at = joined_at, welcome_at = welcome_at,
				t = t, status = last_status}
		_log("итог: " + JSON.stringify(res))
		var f := FileAccess.open("user://party3_%d.txt" % idx, FileAccess.WRITE)
		f.store_string(JSON.stringify(res))
		f.close()
		Net.leave()
		Social.leave_party()
		await get_tree().create_timer(0.5).timeout
		get_tree().quit()


func _ready() -> void:
	Engine.max_fps = 60
	var w := Watcher.new()
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		w.idx = int(args[0])
	if args.size() > 1:
		w.sport = int(args[1])
	for a: String in args:
		if a.begins_with("--join-delay="):
			w.join_delay = float(a.trim_prefix("--join-delay="))
		elif a.begins_with("--load-delay="):
			w.load_delay = float(a.trim_prefix("--load-delay="))
	get_tree().root.add_child.call_deferred(w)
