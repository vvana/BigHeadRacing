extends Node
## Стенд МЕТРИК ПО СЕТИ (10.09): вся цепочка от игры до файла аналитики.
## Этот процесс — КЛИЕНТ с настоящими автозагрузками (Social + Analytics);
## сервер друзей поднимается ВТОРЫМ процессом (ворота игры на портах
## 29982/29992), как в бою. Проверяем: вход игрока сервер записывает сам
## (событие hello), событие из Analytics доезжает и ложится строкой JSON,
## накопленная в оффлайне очередь уезжает при выходе на связь, а мусорное
## событие сервер отбрасывает.
## Запуск: godot --headless --path . res://tools/TestMetrics.tscn
## Вердикт — строка «METRICS TEST: PASS|FAIL».

const PORT := 29982
const SOCIAL_PORT := 29992
const DEADLINE := 45.0

var _t := 0.0
var _pid := -1
var _step := 0
var _uid := ""
var _fails := PackedStringArray()
var _checks := 0
var _seen := {}


func _ready() -> void:
	Engine.max_fps = 60
	_uid = GameState.uid
	# Сервер-ворота отдельным процессом: у него свой Social в роли сервера.
	_pid = OS.create_process(OS.get_executable_path(), ["--headless",
			"--path", ProjectSettings.globalize_path("res://"),
			"res://scenes/Main.tscn", "--", "--server", "--track=grass",
			"--port=%d" % PORT, "--social-port=%d" % SOCIAL_PORT])
	if _pid <= 0:
		_done("не запустить процесс сервера")
		return
	print("[стенд] сервер поднимается, pid %d" % _pid)
	# Метрики в бою собирает автозагрузка; в стенде она выключена
	# (тестовый профиль) — включаем руками, иначе проверять нечего.
	Analytics.enabled = true
	Analytics.set_process(true)
	# Копим событие ДО связи: оно должно уехать, как только связь появится.
	Analytics.push_event("race", {place = 1, size = 4, car = "vz21",
			track = "grass", kills = 2, deaths = 0, ms = 123456,
			online = true, weapons = {"0": 3}, stand = true})


func _process(delta: float) -> void:
	_t += delta
	if _t > DEADLINE:
		_done("не уложились в %d с (шаг %d)" % [int(DEADLINE), _step])
		return
	match _step:
		0:
			# Ждём, пока сервер откроет порт, и выходим на связь.
			if _t > 6.0:
				Social.go_online("127.0.0.1", SOCIAL_PORT)
				_step = 1
		1:
			if Social.connected:
				print("[стенд] на связи, очередь: %d" % Analytics._queue.size())
				_step = 2
		2:
			# Очередь опустела — событие ушло по проводу.
			if Analytics._queue.is_empty():
				Analytics.push_event("ad", {coins = 500, pair = true,
						stand = true})
				Social.send({t = "metric", e = "мусор", d = {stand = true}})
				_step = 3
		3:
			if Analytics._queue.is_empty() and _t > 12.0:
				_check()
				_step = 4


## Читаем файл суток сервера (user:// у процессов общий) и ищем свои строки.
func _check() -> void:
	var path := "%s/%s.jsonl" % [SocialServer.METRICS_DIR,
			Time.get_date_string_from_unix_time(
					int(Time.get_unix_time_from_system()))]
	if not FileAccess.file_exists(path):
		_ok(false, "файл метрик %s создан" % path)
		_done("")
		return
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges() == "":
			continue
		var o: Variant = JSON.parse_string(line)
		if o is Dictionary and str(o.get("uid", "")) == _uid:
			var d: Variant = o.get("d", {})
			# Только строки ЭТОГО прогона: у события стенда есть метка.
			if str(o.e) == "hello" or (d is Dictionary and d.get("stand", false)):
				_seen[str(o.e)] = o
	_ok(_seen.has("hello"), "вход игрока записан сервером (hello)")
	_ok(_seen.has("race"), "накопленный в оффлайне заезд доехал")
	_ok(_seen.has("ad"), "событие рекламы доехало")
	_ok(not _seen.has("мусор"), "незнакомое событие отброшено")
	if _seen.has("race"):
		var r: Dictionary = _seen["race"]
		var d: Dictionary = r.d
		_ok(int(d.get("place", 0)) == 1 and str(d.get("car", "")) == "vz21"
				and int(d.get("kills", 0)) == 2,
				"поля заезда на месте (место, машина, уничтожено)")
		_ok(float(r.get("ts", 0.0)) > 0.0 and int(r.get("cts", 0)) > 0,
				"время сервера и время игрока проставлены")
		_ok(str(r.get("name", "")) != "", "имя игрока подставлено сервером")
	_ok(not FileAccess.file_exists(Analytics.QUEUE_PATH),
			"очередь на диске пуста после отправки")
	_done("")


func _ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(what)
	print("  %s: %s" % [what, "ok" if cond else "FAIL"])


func _done(why: String) -> void:
	set_process(false)
	if why != "":
		_fails.append(why)
	if _pid > 0:
		OS.kill(_pid)
	Social.go_offline()
	print("RESULT: %d/%d ok" % [_checks - _fails.size(), _checks])
	for f in _fails:
		print("FAIL ", f)
	print("METRICS TEST: %s" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit(1 if not _fails.is_empty() else 0)
